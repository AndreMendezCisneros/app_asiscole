"""Modelos de mensajeria (BD central, tabla `asis_mensaje`).

Replica `db/migrations/002_central_schema.sql`. Tres ideas gobiernan este modulo:

* El backend genera el texto y el cliente solo lo renderiza, asi que `texto` ya
  viene redactado en espanol de Peru y nunca se recompone en la app.
* `origen_evento` es la huella del evento del colegio (`"<tipo>:<id_registro>"`).
  Junto con `tenant_id` forma la restriccion unica que hace idempotente la
  ingesta: si el poller reprocesa una fila de `asis_outbox` no se duplica el
  mensaje ni se vuelve a notificar (ADR-04).
* `retenido_hasta` marca la purga por retencion (RNF-11, Ley N.o 29733): a los
  `MESSAGE_RETENTION_MONTHS` meses de la emision el mensaje se borra o anonimiza.
"""

from __future__ import annotations

import uuid
from calendar import monthrange
from datetime import datetime

from django.conf import settings
from django.db import models
from django.utils import timezone

# --- Tipos de mensaje ---------------------------------------------------------
#: Los cinco valores del enum `TipoMensaje` de `docs/openapi.yaml` y del CHECK de
#: `asis_mensaje.tipo`. Anadir uno obliga a registrar su plantilla (ver
#: `apps.mensajeria.plantillas.registry`).
TIPO_ENTRADA = "entrada"
TIPO_SALIDA = "salida"
TIPO_INCIDENCIA = "incidencia"
TIPO_AVISO = "aviso"
TIPO_PERSONALIZADO = "personalizado"

TIPOS_MENSAJE = (
    (TIPO_ENTRADA, "Entrada al colegio"),
    (TIPO_SALIDA, "Salida del colegio"),
    (TIPO_INCIDENCIA, "Incidencia"),
    (TIPO_AVISO, "Aviso institucional"),
    (TIPO_PERSONALIZADO, "Mensaje personalizado"),
)

#: Solo los codigos, para validar sin recorrer las tuplas.
CODIGOS_TIPO_MENSAJE: tuple[str, ...] = tuple(codigo for codigo, _ in TIPOS_MENSAJE)


def sumar_meses(momento: datetime, meses: int) -> datetime:
    """Suma meses de calendario a una fecha, recortando el dia si no existe.

    Se resuelve a mano en lugar de con `dateutil` para no anadir una dependencia
    por una operacion que solo se usa en la retencion. El 31 de enero mas un mes
    da el 28 (o 29) de febrero.

    Args:
        momento: Fecha de partida, con zona horaria.
        meses: Cuantos meses sumar.

    Returns:
        La fecha resultante, conservando la hora y la zona.
    """
    total = momento.month - 1 + meses
    anio = momento.year + total // 12
    mes = total % 12 + 1
    dia = min(momento.day, monthrange(anio, mes)[1])
    return momento.replace(year=anio, month=mes, day=dia)


def fecha_limite_retencion() -> datetime:
    """Devuelve la fecha de purga por defecto de un mensaje nuevo (RNF-11)."""
    return sumar_meses(timezone.now(), int(settings.MESSAGE_RETENTION_MONTHS))


class Mensaje(models.Model):
    """Mensaje de la bandeja del apoderado (`asis_mensaje`).

    Attributes:
        id: UUID que viaja como `message_id` en el push. Da idempotencia al
            cliente: si la notificacion llega dos veces se muestra una sola.
        tenant_id: Colegio que origino el mensaje.
        origen_evento: Huella del evento del colegio, `"entrada:1042"`. Los
            avisos y los mensajes personalizados no nacen de un evento y lo
            dejan en `NULL`, por eso pueden repetirse.
        metadata: Datos tecnicos para el deep-link de la app (id de la falta,
            grado, seccion). Nunca se vuelca a un log.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    apoderado = models.ForeignKey(
        "cuentas.Apoderado",
        on_delete=models.CASCADE,
        db_column="apoderado_id",
        related_name="mensajes",
    )
    tenant_id = models.TextField(verbose_name="Colegio (tenant)")
    id_estudiante = models.IntegerField(null=True, blank=True)
    tipo = models.TextField(choices=TIPOS_MENSAJE)
    texto = models.TextField(verbose_name="Texto generado por el backend")
    metadata = models.JSONField(default=dict, blank=True)
    origen_evento = models.TextField(null=True, blank=True)
    emitido_en = models.DateTimeField(default=timezone.now)
    entregado = models.BooleanField(default=False)
    entregado_en = models.DateTimeField(null=True, blank=True)
    leido = models.BooleanField(default=False)
    leido_en = models.DateTimeField(null=True, blank=True)
    retenido_hasta = models.DateTimeField(default=fecha_limite_retencion)

    class Meta:
        db_table = "asis_mensaje"
        verbose_name = "Mensaje"
        verbose_name_plural = "Mensajes"
        constraints = [
            # Idempotencia de la ingesta. La condicion replica el indice parcial
            # del esquema canonico: los mensajes sin evento de origen (avisos,
            # personalizados) quedan fuera y pueden repetirse.
            # Un evento genera un mensaje por apoderado (hermanos / varios padres).
            models.UniqueConstraint(
                fields=["apoderado", "tenant_id", "origen_evento"],
                condition=models.Q(origen_evento__isnull=False),
                name="asis_uniq_mensaje_origen",
            ),
            models.CheckConstraint(
                condition=models.Q(tipo__in=list(CODIGOS_TIPO_MENSAJE)),
                name="asis_mensaje_tipo_valido",
            ),
        ]
        indexes = [
            # Bandeja: los mensajes de un apoderado, del mas nuevo al mas viejo.
            models.Index(fields=["apoderado", "-emitido_en"], name="asis_idx_mensaje_bandeja"),
            # Barrido de la purga por retencion.
            models.Index(fields=["retenido_hasta"], name="asis_idx_mensaje_retencion"),
        ]

    def __str__(self) -> str:
        # Ni el texto ni el nombre del estudiante: un repr accidental no puede
        # acabar escribiendo datos de un menor en un log (Ley N.o 29733).
        return f"mensaje:{self.pk}"

    @property
    def vencido(self) -> bool:
        """True si el mensaje ya paso su plazo de retencion."""
        return self.retenido_hasta <= timezone.now()

    def marcar_entregado(self) -> None:
        """Deja constancia de que el push salio hacia el dispositivo."""
        ahora = timezone.now()
        # `update` en lugar de `save`: no se pisan campos que otra tarea pudo
        # cambiar mientras el proveedor de push respondia.
        Mensaje.objects.filter(pk=self.pk, entregado=False).update(
            entregado=True, entregado_en=ahora
        )
        self.entregado = True
        self.entregado_en = ahora
