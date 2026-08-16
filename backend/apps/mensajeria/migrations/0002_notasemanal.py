import uuid

import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("mensajeria", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="NotaSemanal",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("tenant_id", models.TextField()),
                ("id_estudiante", models.IntegerField()),
                ("id_registro", models.IntegerField()),
                ("semana_codigo", models.TextField(blank=True, null=True)),
                ("semana_etiqueta", models.TextField(blank=True, null=True)),
                ("fecha_inicio", models.DateField(blank=True, null=True)),
                ("fecha_fin", models.DateField(blank=True, null=True)),
                ("nota", models.TextField()),
                ("nota_maxima", models.TextField(blank=True, null=True)),
                ("area_codigo", models.TextField(blank=True, null=True)),
                ("area_nombre", models.TextField(blank=True, null=True)),
                ("carrera", models.TextField(blank=True, null=True)),
                ("registrado_en", models.DateTimeField(blank=True, null=True)),
                (
                    "emitido_en",
                    models.DateTimeField(default=django.utils.timezone.now),
                ),
            ],
            options={
                "verbose_name": "Nota semanal",
                "verbose_name_plural": "Notas semanales",
                "db_table": "asis_nota",
            },
        ),
        migrations.AddIndex(
            model_name="notasemanal",
            index=models.Index(
                fields=["tenant_id", "id_estudiante", "-fecha_inicio"],
                name="asis_idx_nota_estudiante",
            ),
        ),
        migrations.AddConstraint(
            model_name="notasemanal",
            constraint=models.UniqueConstraint(
                fields=("tenant_id", "id_estudiante", "id_registro"),
                name="asis_uniq_nota_origen",
            ),
        ),
    ]
