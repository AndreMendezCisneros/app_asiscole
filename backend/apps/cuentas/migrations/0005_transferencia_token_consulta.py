from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("cuentas", "0004_terminos_consentimiento"),
    ]

    operations = [
        migrations.AddField(
            model_name="transferenciasesion",
            name="token_consulta",
            field=models.CharField(
                blank=True, max_length=64, null=True, unique=True
            ),
        ),
    ]
