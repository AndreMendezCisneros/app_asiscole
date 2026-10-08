"""Semilla de `asis_app_version` para iOS.

El número de build de iOS lo asigna Codemagic (último de TestFlight + 1) y no
sigue al `versionCode` de Android. `url_tienda` queda vacía hasta que exista la
ficha en la App Store; mientras tanto la app no ofrece un enlace roto.
"""

from django.db import migrations


def sembrar(apps, schema_editor):
    VersionApp = apps.get_model("administracion", "VersionApp")
    VersionApp.objects.get_or_create(
        plataforma="ios",
        defaults={
            "min_soportada": 1,
            "ultima_disponible": 1,
            "url_tienda": None,
            "mensaje": "Hay una versión nueva de Asiscole Messenger.",
        },
    )


def vaciar(apps, schema_editor):
    VersionApp = apps.get_model("administracion", "VersionApp")
    VersionApp.objects.filter(plataforma="ios").delete()


class Migration(migrations.Migration):
    dependencies = [
        ("administracion", "0003_semilla_version_app"),
    ]

    operations = [
        migrations.RunPython(sembrar, vaciar),
    ]
