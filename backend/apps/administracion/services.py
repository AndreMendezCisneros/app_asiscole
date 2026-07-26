"""Servicios de administración: cuentas, avisos y feature flags."""

from __future__ import annotations

import logging

from django.db.models import Q

from apps.administracion.models import FeatureFlag
from apps.common.errors import ValidationError
from apps.cuentas.models import (
    CUENTA_ACTIVA,
    CUENTA_SUSPENDIDA,
    PREFIJO_IDENTIDAD_ADMIN,
    SESION_ACTIVA,
    Apoderado,
    SesionActiva,
)
from apps.cuentas.services import enmascarar_telefono
from apps.cuentas.suspension import forzar_cierre_sesion, reactivar, suspender
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from apps.mensajeria.models import TIPO_AVISO, Mensaje
from apps.mensajeria.plantillas.base import ContextoEvento
from apps.mensajeria.plantillas.registry import renderizar

logger = logging.getLogger("asiscole.administracion")


def listar_flags() -> dict[str, bool]:
    """Devuelve los flags; garantiza `notas=false` por defecto."""
    FeatureFlag.objects.get_or_create(clave="notas", defaults={"activo": False})
    return {f.clave: f.activo for f in FeatureFlag.objects.all()}


def listar_apoderados(
    *,
    buscar: str | None = None,
    estado: str | None = None,
    cursor: str | None = None,
    limite: int = 50,
) -> dict:
    qs = Apoderado.objects.exclude(telefono__startswith=PREFIJO_IDENTIDAD_ADMIN).exclude(
        estado="eliminado"
    )
    if estado in (CUENTA_ACTIVA, CUENTA_SUSPENDIDA):
        qs = qs.filter(estado=estado)
    if buscar:
        # Solo busca por alias o id; nunca por teléfono en claro en logs.
        if buscar.isdigit():
            qs = qs.filter(Q(pk=int(buscar)) | Q(nombre_alias__icontains=buscar))
        else:
            qs = qs.filter(nombre_alias__icontains=buscar)
    if cursor and cursor.isdigit():
        qs = qs.filter(pk__lt=int(cursor))

    filas = list(qs.order_by("-pk")[: limite + 1])
    hay_mas = len(filas) > limite
    pagina = filas[:limite]
    items = []
    for apo in pagina:
        sesion = (
            SesionActiva.objects.filter(apoderado=apo, estado=SESION_ACTIVA)
            .order_by("-ultima_actividad_en")
            .first()
        )
        estudiantes = [
            {
                "id": v.id_estudiante,
                "nombre": v.nombre_estudiante,
                "grado": v.grado or "",
                "seccion": v.seccion or "",
                "nivel": v.nivel or "",
                "colegio": v.tenant_id,
                "tenant_id": v.tenant_id,
                "activo": apo.estudiante_activo_id == v.id_estudiante,
            }
            for v in Directorio.objects.filter(
                telefono=apo.telefono, estado_vinculo=VINCULO_ACTIVO
            )[:20]
        ]
        items.append(
            {
                "id": apo.pk,
                "alias": apo.nombre_alias,
                "telefono": enmascarar_telefono(apo.telefono),
                "estado": apo.estado,
                "motivo_suspension": apo.motivo_suspension,
                "sesion_activa": sesion is not None,
                "ultimo_dispositivo": sesion.modelo if sesion else None,
                "ultima_actividad_en": (
                    sesion.ultima_actividad_en.isoformat() if sesion else None
                ),
                "estudiantes": estudiantes,
            }
        )
    next_cursor = str(pagina[-1].pk) if hay_mas and pagina else None
    return {"items": items, "next_cursor": next_cursor}


def suspender_cuenta(
    apoderado_id: int,
    *,
    motivo: str,
    actor: str | None,
    notificar_push: bool = True,
) -> None:
    if not motivo or len(motivo.strip()) < 5:
        raise ValidationError("El motivo debe tener al menos 5 caracteres.")
    apo = Apoderado.objects.filter(pk=apoderado_id).first()
    if apo is None or apo.es_administrador:
        raise ValidationError("No se encontró la cuenta indicada.")
    suspender(apo, motivo.strip(), actor=actor, notificar_push=notificar_push)


def reactivar_cuenta(apoderado_id: int, *, actor: str | None) -> None:
    apo = Apoderado.objects.filter(pk=apoderado_id).first()
    if apo is None or apo.es_administrador:
        raise ValidationError("No se encontró la cuenta indicada.")
    reactivar(apo, actor=actor)


def cerrar_sesion_cuenta(apoderado_id: int, *, actor: str | None) -> None:
    apo = Apoderado.objects.filter(pk=apoderado_id).first()
    if apo is None or apo.es_administrador:
        raise ValidationError("No se encontró la cuenta indicada.")
    forzar_cierre_sesion(apo, actor=actor)


def enviar_aviso(
    *,
    texto: str,
    nivel: str | None = None,
    grado: str | None = None,
    seccion: str | None = None,
) -> dict:
    """Crea mensajes tipo aviso filtrados por nivel/grado/sección (RF-B04)."""
    cuerpo = (texto or "").strip()
    if not cuerpo:
        raise ValidationError("El texto del aviso es obligatorio.")

    qs = Directorio.objects.filter(estado_vinculo=VINCULO_ACTIVO)
    if nivel:
        qs = qs.filter(nivel=nivel)
    if grado:
        qs = qs.filter(grado=grado)
    if seccion:
        qs = qs.filter(seccion=seccion)

    telefonos = list(qs.values_list("telefono", flat=True).distinct())
    apoderados = list(
        Apoderado.objects.filter(telefono__in=telefonos, estado=CUENTA_ACTIVA).exclude(
            telefono__startswith=PREFIJO_IDENTIDAD_ADMIN
        )
    )

    ctx = ContextoEvento(tipo=TIPO_AVISO, texto_libre=cuerpo, colegio="Asiscole")
    redactado = renderizar(TIPO_AVISO, ctx)

    from apps.mensajeria.tasks import enviar_push_mensaje

    creados = 0
    for apo in apoderados:
        mensaje = Mensaje.objects.create(
            apoderado=apo,
            tenant_id="institucional",
            id_estudiante=None,
            tipo=TIPO_AVISO,
            texto=redactado,
            metadata={"nivel": nivel, "grado": grado, "seccion": seccion},
            origen_evento=None,
        )
        enviar_push_mensaje.delay(str(mensaje.pk))
        creados += 1

    logger.info("aviso_encolado", extra={"destinatarios": creados})
    return {"destinatarios": creados}
