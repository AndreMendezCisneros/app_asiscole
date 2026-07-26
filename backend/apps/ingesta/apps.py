"""Registro de la app `ingesta`."""

from __future__ import annotations

import logging
import os
import sys
import threading

from django.apps import AppConfig

logger = logging.getLogger("asiscole.ingesta")


class IngestaConfig(AppConfig):
    """Lectura periodica de los eventos de asistencia e incidencias."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.ingesta"
    label = "ingesta"
    verbose_name = "Ingesta de eventos"

    def ready(self) -> None:
        """Arranca poller en-proceso cuando no hay Celery (dev local)."""
        from django.conf import settings

        if not getattr(settings, "POLL_OUTBOX_INLINE", False):
            return
        # Solo junto a runserver (no migrate / poll_outbox / tests).
        if "runserver" not in sys.argv:
            return
        # Evitar doble arranque con el autoreloader de Django.
        if os.environ.get("RUN_MAIN") != "true":
            return
        if getattr(self, "_poller_inline_started", False):
            return
        self._poller_inline_started = True

        intervalo = float(getattr(settings, "POLL_OUTBOX_INLINE_SECONDS", 15))
        stop = threading.Event()

        def _bucle() -> None:
            logger.info("poller_inline_iniciado", extra={"intervalo_s": intervalo})
            while not stop.is_set():
                try:
                    from apps.ingesta.tasks import poll_outbox_colegios

                    poll_outbox_colegios()
                except Exception:  # noqa: BLE001
                    logger.exception("poller_inline_error")
                stop.wait(intervalo)

        hilo = threading.Thread(
            target=_bucle,
            name="asiscole-poll-outbox-inline",
            daemon=True,
        )
        hilo.start()
