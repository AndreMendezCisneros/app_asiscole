from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("directorio", "0001_initial"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="directorio",
            index=models.Index(
                fields=["tenant_id", "id_estudiante"],
                name="asis_idx_dir_tenant_est",
            ),
        ),
    ]
