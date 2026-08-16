"""Actualiza el copy de versión al nombre visible Asis Messenger."""

from django.db import migrations

MENSAJE = "Hay una versión nueva de Asis Messenger."


def actualizar(apps, schema_editor):
    VersionApp = apps.get_model("administracion", "VersionApp")
    VersionApp.objects.filter(plataforma="android").update(mensaje=MENSAJE)


def revertir(apps, schema_editor):
    VersionApp = apps.get_model("administracion", "VersionApp")
    VersionApp.objects.filter(plataforma="android").update(
        mensaje="Hay una versión nueva de Asiscole Messenger.",
    )


class Migration(migrations.Migration):
    dependencies = [
        ("administracion", "0003_semilla_version_app"),
    ]

    operations = [
        migrations.RunPython(actualizar, revertir),
    ]
