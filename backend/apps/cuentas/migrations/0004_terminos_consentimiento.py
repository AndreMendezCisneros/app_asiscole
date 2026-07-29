from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("cuentas", "0003_confirmacion_incidencia"),
    ]

    operations = [
        migrations.AddField(
            model_name="apoderado",
            name="terminos_version",
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="apoderado",
            name="terminos_aceptados_en",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
