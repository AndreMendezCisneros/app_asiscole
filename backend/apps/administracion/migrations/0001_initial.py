import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="FeatureFlag",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True, primary_key=True, serialize=False, verbose_name="ID"
                    ),
                ),
                ("clave", models.TextField(unique=True)),
                ("activo", models.BooleanField(default=False)),
                ("actualizado_en", models.DateTimeField(default=django.utils.timezone.now)),
            ],
            options={
                "verbose_name": "Feature flag",
                "verbose_name_plural": "Feature flags",
                "db_table": "asis_feature_flag",
            },
        ),
    ]
