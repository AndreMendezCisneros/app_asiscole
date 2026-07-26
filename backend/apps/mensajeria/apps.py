"""Registro de la app `mensajeria`."""

from django.apps import AppConfig


class MensajeriaConfig(AppConfig):
    """Bandeja de mensajes del apoderado y notificaciones push."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.mensajeria"
    label = "mensajeria"
    verbose_name = "Mensajeria"
