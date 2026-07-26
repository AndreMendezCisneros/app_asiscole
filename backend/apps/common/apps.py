"""Registro de la app `common`."""

from django.apps import AppConfig


class CommonConfig(AppConfig):
    """Piezas compartidas por el resto de apps del canal."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.common"
    label = "common"
    verbose_name = "Comun"
