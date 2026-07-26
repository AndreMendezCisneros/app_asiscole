import uuid

import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models

import apps.mensajeria.models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        ("cuentas", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="Mensaje",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4, editable=False, primary_key=True, serialize=False
                    ),
                ),
                ("tenant_id", models.TextField(verbose_name="Colegio (tenant)")),
                ("id_estudiante", models.IntegerField(blank=True, null=True)),
                ("tipo", models.TextField()),
                ("texto", models.TextField(verbose_name="Texto generado por el backend")),
                ("metadata", models.JSONField(blank=True, default=dict)),
                ("origen_evento", models.TextField(blank=True, null=True)),
                ("emitido_en", models.DateTimeField(default=django.utils.timezone.now)),
                ("entregado", models.BooleanField(default=False)),
                ("entregado_en", models.DateTimeField(blank=True, null=True)),
                ("leido", models.BooleanField(default=False)),
                ("leido_en", models.DateTimeField(blank=True, null=True)),
                (
                    "retenido_hasta",
                    models.DateTimeField(default=apps.mensajeria.models.fecha_limite_retencion),
                ),
                (
                    "apoderado",
                    models.ForeignKey(
                        db_column="apoderado_id",
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="mensajes",
                        to="cuentas.apoderado",
                    ),
                ),
            ],
            options={
                "verbose_name": "Mensaje",
                "verbose_name_plural": "Mensajes",
                "db_table": "asis_mensaje",
            },
        ),
        migrations.AddIndex(
            model_name="mensaje",
            index=models.Index(
                fields=["apoderado", "-emitido_en"], name="asis_idx_mensaje_bandeja"
            ),
        ),
        migrations.AddIndex(
            model_name="mensaje",
            index=models.Index(fields=["retenido_hasta"], name="asis_idx_mensaje_retencion"),
        ),
        migrations.AddConstraint(
            model_name="mensaje",
            constraint=models.UniqueConstraint(
                condition=models.Q(("origen_evento__isnull", False)),
                fields=("apoderado", "tenant_id", "origen_evento"),
                name="asis_uniq_mensaje_origen",
            ),
        ),
        migrations.AddConstraint(
            model_name="mensaje",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    (
                        "tipo__in",
                        ["entrada", "salida", "incidencia", "aviso", "personalizado"],
                    )
                ),
                name="asis_mensaje_tipo_valido",
            ),
        ),
    ]
