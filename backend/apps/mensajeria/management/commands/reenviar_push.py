"""Reenvía push de mensajes no entregados (útil en local tras registrar FCM)."""

from __future__ import annotations

from django.core.management.base import BaseCommand, CommandError

from apps.cuentas.models import Apoderado
from apps.mensajeria.tasks import reintentar_push_pendientes


class Command(BaseCommand):
    help = "Reenvía notificaciones push pendientes de un apoderado (por id)."

    def add_arguments(self, parser) -> None:
        parser.add_argument("apoderado_id", type=int)
        parser.add_argument("--limite", type=int, default=30)

    def handle(self, *args, **opciones) -> None:
        apo_id = opciones["apoderado_id"]
        try:
            apoderado = Apoderado.objects.get(pk=apo_id)
        except Apoderado.DoesNotExist as exc:
            raise CommandError(f"Apoderado {apo_id} no existe.") from exc

        enviados = reintentar_push_pendientes(apoderado, limite=opciones["limite"])
        self.stdout.write(
            self.style.SUCCESS(
                f"apoderado_id={apo_id} push_reenviados={enviados}"
            )
        )
