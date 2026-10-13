from django.db import migrations, models
import django.utils.timezone


class Migration(migrations.Migration):

    dependencies = [
        ("cuentas", "0005_transferencia_token_consulta"),
    ]

    operations = [
        migrations.CreateModel(
            name="BajaCuenta",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("hash_telefono", models.CharField(max_length=64)),
                ("hash_documento", models.CharField(max_length=64)),
                (
                    "creado_en",
                    models.DateTimeField(default=django.utils.timezone.now),
                ),
            ],
            options={
                "verbose_name": "Baja de cuenta",
                "verbose_name_plural": "Bajas de cuenta",
                "db_table": "asis_baja_cuenta",
            },
        ),
        migrations.AddConstraint(
            model_name="bajacuenta",
            constraint=models.UniqueConstraint(
                fields=("hash_telefono", "hash_documento"),
                name="asis_baja_cuenta_unica",
            ),
        ),
        migrations.AddIndex(
            model_name="bajacuenta",
            index=models.Index(
                fields=["hash_telefono"],
                name="asis_idx_baja_telefono",
            ),
        ),
    ]
