"""Desactiva los tokens de push de cuentas que ya no tienen sesion abierta."""

from __future__ import annotations

from django.core.management.base import BaseCommand

from apps.cuentas.services import desactivar_push_sin_sesion


class Command(BaseCommand):
    help = (
        "Desactiva los push token de apoderados sin sesion activa. "
        "Son los que quedaron vivos cuando el logout no llego al servidor."
    )

    def add_arguments(self, parser) -> None:
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Cuenta los tokens afectados sin desactivarlos.",
        )

    def handle(self, *args, **opciones) -> None:
        simular = bool(opciones["dry_run"])
        total = desactivar_push_sin_sesion(simular=simular)
        verbo = "se desactivarian" if simular else "desactivados"
        self.stdout.write(self.style.SUCCESS(f"tokens {verbo}={total}"))
