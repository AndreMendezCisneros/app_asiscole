"""Instancia de Celery del canal Asiscole.

El docker-compose la invoca como ``celery -A config worker`` y ``celery -A config beat``.
La configuracion (broker, backend y ``beat_schedule``) vive en ``config/settings.py``
bajo el prefijo ``CELERY_``.
"""

from __future__ import annotations

import logging
import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

logger = logging.getLogger("asiscole.celery")

app = Celery("asiscole")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()


@app.task(bind=True, ignore_result=True)
def debug_task(self) -> None:
    """Tarea de humo para comprobar que el worker consume la cola."""
    # Solo metadatos: nunca datos personales en la salida de una tarea.
    logger.info("celery_ok", extra={"task_id": self.request.id})
