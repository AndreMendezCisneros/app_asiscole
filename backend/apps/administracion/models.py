"""Modelos de administración del canal (BD central)."""

from __future__ import annotations

from django.db import models
from django.utils import timezone


class FeatureFlag(models.Model):
    """Flag remoto (`asis_feature_flag`), p. ej. módulo de notas (RF-H03)."""

    clave = models.TextField(unique=True)
    activo = models.BooleanField(default=False)
    actualizado_en = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "asis_feature_flag"
        verbose_name = "Feature flag"
        verbose_name_plural = "Feature flags"

    def __str__(self) -> str:
        return f"flag:{self.clave}"

    def save(self, *args, **kwargs):
        self.actualizado_en = timezone.now()
        super().save(*args, **kwargs)
