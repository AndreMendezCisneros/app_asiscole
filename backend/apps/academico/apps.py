"""Registro de la app `academico`."""

from django.apps import AppConfig


class AcademicoConfig(AppConfig):
    """Espejo de solo lectura del esquema de cada colegio.

    Sus modelos son `managed = False`: el canal no crea, no altera y no migra
    nada del sistema escolar existente.
    """

    default_auto_field = "django.db.models.AutoField"
    name = "apps.academico"
    label = "academico"
    verbose_name = "Academico (solo lectura)"
