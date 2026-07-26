from django.db import migrations, models
import django.utils.timezone


class Migration(migrations.Migration):
    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="CursorIngesta",
            fields=[
                ("tenant_id", models.TextField(primary_key=True, serialize=False)),
                ("ultimo_id", models.BigIntegerField(default=0)),
                (
                    "actualizado_en",
                    models.DateTimeField(default=django.utils.timezone.now),
                ),
            ],
            options={
                "verbose_name": "Cursor de ingesta",
                "verbose_name_plural": "Cursores de ingesta",
                "db_table": "asis_cursor_ingesta",
            },
        ),
    ]
