"""Modelos de ingesta.

`asis_outbox` vive en cada BD de colegio (managed=False). El cursor del poller
vive en la BD central para saber hasta dónde se procesó por tenant.
"""

from __future__ import annotations

from django.db import models
from django.utils import timezone


class OutboxEvento(models.Model):
    """Fila de `asis_outbox` en la BD del colegio. Solo lectura + marcado procesado."""

    id = models.BigAutoField(primary_key=True)
    tipo = models.TextField()
    id_estudiante = models.IntegerField()
    id_registro = models.IntegerField()
    payload = models.JSONField(default=dict)
    procesado = models.BooleanField(default=False)
    intentos = models.IntegerField(default=0)
    ultimo_error = models.TextField(null=True, blank=True)
    creado_en = models.DateTimeField()
    procesado_en = models.DateTimeField(null=True, blank=True)

    class Meta:
        managed = False
        db_table = "asis_outbox"


class CursorIngesta(models.Model):
    """Último id de outbox procesado por colegio (`asis_cursor_ingesta`)."""

    tenant_id = models.TextField(primary_key=True)
    ultimo_id = models.BigIntegerField(default=0)
    actualizado_en = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "asis_cursor_ingesta"
        verbose_name = "Cursor de ingesta"
        verbose_name_plural = "Cursores de ingesta"

    def __str__(self) -> str:
        return f"cursor:{self.tenant_id}"
