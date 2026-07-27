import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("cuentas", "0002_estudiante_activo"),
    ]

    operations = [
        migrations.CreateModel(
            name="ConfirmacionIncidencia",
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
                ("tenant_id", models.TextField()),
                ("id_incidencia_colegio", models.IntegerField()),
                (
                    "confirmada_en",
                    models.DateTimeField(default=django.utils.timezone.now),
                ),
                (
                    "apoderado",
                    models.ForeignKey(
                        db_column="apoderado_id",
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="confirmaciones_incidencia",
                        to="cuentas.apoderado",
                    ),
                ),
            ],
            options={
                "verbose_name": "Confirmacion de incidencia",
                "verbose_name_plural": "Confirmaciones de incidencia",
                "db_table": "asis_confirmacion_incidencia",
            },
        ),
        migrations.AddConstraint(
            model_name="confirmacionincidencia",
            constraint=models.UniqueConstraint(
                fields=("apoderado", "tenant_id", "id_incidencia_colegio"),
                name="asis_uniq_conf_incidencia",
            ),
        ),
        migrations.AddIndex(
            model_name="confirmacionincidencia",
            index=models.Index(
                fields=["apoderado", "tenant_id"],
                name="asis_idx_conf_apo_ten",
            ),
        ),
    ]
