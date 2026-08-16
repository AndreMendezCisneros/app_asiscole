"""Semilla de `asis_app_version`: no bloquear los APK ya repartidos."""

from django.db import migrations

FICHA_PLAY = (
    "https://play.google.com/store/apps/details?id=pe.asiscole.asiscole_app"
)


def sembrar(apps, schema_editor):
    VersionApp = apps.get_model("administracion", "VersionApp")
    # min_soportada=1: el APK 1.0.0+1 que ya está en teléfonos sigue sirviendo.
    # ultima_disponible=2: coincide con 1.0.1+2 de este trabajo, para que el
    # cliente viejo vea el aviso opcional y no un bloqueo.
    VersionApp.objects.get_or_create(
        plataforma="android",
        defaults={
            "min_soportada": 1,
            "ultima_disponible": 2,
            "url_tienda": FICHA_PLAY,
            "mensaje": "Hay una versión nueva de Asiscole Messenger.",
        },
    )


def vaciar(apps, schema_editor):
    VersionApp = apps.get_model("administracion", "VersionApp")
    VersionApp.objects.filter(plataforma="android").delete()


class Migration(migrations.Migration):
    dependencies = [
        ("administracion", "0002_versionapp"),
    ]

    operations = [
        migrations.RunPython(sembrar, vaciar),
    ]
