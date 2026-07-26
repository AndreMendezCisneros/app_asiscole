"""Comando: vaciar asis_outbox → asis_mensaje (sin Celery)."""

from __future__ import annotations

from django.core.management.base import BaseCommand

from apps.ingesta.tasks import poll_outbox_colegios


class Command(BaseCommand):
    help = "Procesa pendientes de asis_outbox en todos los colegios (una pasada)."

    def handle(self, *args, **options) -> None:
        resumen = poll_outbox_colegios()
        for tenant_id, contadores in resumen.items():
            self.stdout.write(
                f"{tenant_id}: leidos={contadores.get('leidos', 0)} "
                f"creados={contadores.get('creados', 0)} "
                f"errores={contadores.get('errores', 0)}"
            )
