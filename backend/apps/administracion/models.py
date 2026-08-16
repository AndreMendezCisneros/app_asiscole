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


PLATAFORMAS_APP = (("android", "Android"), ("ios", "iOS"))


class VersionApp(models.Model):
    """Politica de versiones por plataforma (`asis_app_version`).

    Existe para poder cortar una version con un fallo grave sin depender de que
    el apoderado abra la tienda. `min_soportada` es el `versionCode` minimo que
    el canal acepta; por debajo, la app se bloquea y solo ofrece actualizar.

    Se siembra con `min_soportada = 1` a proposito: subir ese numero deja fuera a
    todo el que tenga el APK anterior, asi que es una decision explicita.
    """

    plataforma = models.TextField(unique=True, choices=PLATAFORMAS_APP)
    min_soportada = models.PositiveIntegerField(default=1)
    ultima_disponible = models.PositiveIntegerField(default=1)
    mensaje = models.TextField(null=True, blank=True)
    url_tienda = models.TextField(null=True, blank=True)
    actualizado_en = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "asis_app_version"
        verbose_name = "Versión de app"
        verbose_name_plural = "Versiones de app"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(min_soportada__lte=models.F("ultima_disponible")),
                name="asis_app_version_min_coherente",
            ),
        ]

    def __str__(self) -> str:
        return f"version:{self.plataforma}"

    def save(self, *args, **kwargs):
        self.actualizado_en = timezone.now()
        super().save(*args, **kwargs)
