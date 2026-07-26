"""Registro de la app `cuentas`."""

from django.apps import AppConfig


class CuentasConfig(AppConfig):
    """Cuentas del apoderado y ciclo de vida de la sesion."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.cuentas"
    label = "cuentas"
    verbose_name = "Cuentas de apoderado"

    def ready(self) -> None:
        """Registra las extensiones de esquema de los dos tipos de token."""
        from apps.cuentas import schema  # noqa: F401
