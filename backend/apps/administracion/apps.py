"""Registro de la app `administracion`."""

from django.apps import AppConfig


class AdministracionConfig(AppConfig):
    """Operacion y soporte del canal."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.administracion"
    label = "administracion"
    verbose_name = "Administracion del canal"
