from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("cuentas", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="apoderado",
            name="estudiante_activo_id",
            field=models.IntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="apoderado",
            name="estudiante_activo_tenant",
            field=models.TextField(blank=True, null=True),
        ),
    ]
