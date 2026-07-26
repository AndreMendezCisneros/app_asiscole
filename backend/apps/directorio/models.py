"""Modelos del directorio telefonico (BD central, tablas `asis_*`).

`asis_directorio` es la proyeccion indexada del vinculo
telefono -> (colegio, estudiante) que describe ADR-05. La fuente de verdad sigue
siendo `estudiantes.telefono_contacto` de cada BD de colegio; esta tabla es una
replica minima que permite resolver un login sin recorrer todos los colegios.

Este modelo replica exactamente `db/migrations/002_central_schema.sql`. Si algun
dia divergen, manda Django y hay que actualizar el SQL de referencia.
"""

from __future__ import annotations

from django.db import models

#: Como llego el vinculo al directorio.
ORIGEN_AUTOMATICO = "resuelto_automatico"
ORIGEN_ADMIN = "registrado_admin"
ORIGENES = (
    (ORIGEN_AUTOMATICO, "Resuelto automaticamente desde la BD del colegio"),
    (ORIGEN_ADMIN, "Registrado a mano por un administrador del canal"),
)

#: Estados del vinculo. Un vinculo `inactivo` sigue en la tabla por trazabilidad
#: pero no habilita login ni entrega de mensajes.
VINCULO_ACTIVO = "activo"
VINCULO_INACTIVO = "inactivo"


class Directorio(models.Model):
    """Vinculo telefono <-> estudiante <-> colegio (`asis_directorio`).

    Attributes:
        telefono: Telefono del apoderado ya normalizado a E.164. Es la clave de
            busqueda del login y de la entrega de mensajes.
        tenant_id: Identificador del colegio; unica forma de saber a que BD
            pertenece `id_estudiante`, porque los IDs se repiten entre colegios.
        codigo_barras: El "documento del estudiante" del login (ADR-01).
    """

    telefono = models.TextField(
        verbose_name="Telefono E.164",
        help_text="Telefono del apoderado normalizado con apps.common.phone.",
    )
    tenant_id = models.TextField(verbose_name="Colegio (tenant)")
    id_estudiante = models.IntegerField(verbose_name="Id del estudiante en su colegio")
    codigo_barras = models.TextField(verbose_name="Documento del estudiante")
    nombre_estudiante = models.TextField(verbose_name="Nombre del estudiante")
    grado = models.TextField(null=True, blank=True)
    seccion = models.TextField(null=True, blank=True)
    nivel = models.TextField(null=True, blank=True)
    relacion = models.TextField(null=True, blank=True, default="apoderado")
    origen = models.TextField(null=True, blank=True, choices=ORIGENES)
    estado_vinculo = models.TextField(null=True, blank=True, default=VINCULO_ACTIVO)
    sincronizado_en = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "asis_directorio"
        verbose_name = "Vinculo del directorio"
        verbose_name_plural = "Directorio telefonico"
        constraints = [
            models.UniqueConstraint(
                fields=["telefono", "tenant_id", "id_estudiante"],
                name="asis_directorio_unico",
            ),
            models.CheckConstraint(
                condition=models.Q(origen__isnull=True)
                | models.Q(origen__in=[ORIGEN_AUTOMATICO, ORIGEN_ADMIN]),
                name="asis_directorio_origen_valido",
            ),
        ]
        indexes = [
            # Camino caliente del login: "que estudiantes tiene este telefono".
            models.Index(fields=["telefono"], name="asis_idx_directorio_telefono"),
        ]

    def __str__(self) -> str:
        # Nunca el telefono ni el nombre: un repr accidental no puede acabar
        # escribiendo datos de un menor en un log (Ley N.o 29733).
        return f"directorio:{self.pk}"
