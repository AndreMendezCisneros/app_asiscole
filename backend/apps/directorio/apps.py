"""Registro de la app `directorio`."""

from django.apps import AppConfig


class DirectorioConfig(AppConfig):
    """Directorio telefonico replicado en la BD central."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.directorio"
    label = "directorio"
    verbose_name = "Directorio telefonico"
