"""Tareas Celery del poller de outbox."""

from __future__ import annotations

import logging

from celery import shared_task
from django.conf import settings

from apps.directorio import circuit_breaker
from apps.ingesta.services import procesar_lote_tenant

logger = logging.getLogger("asiscole.ingesta")


@shared_task(name="apps.ingesta.tasks.poll_outbox_colegios", ignore_result=True)
def poll_outbox_colegios() -> dict[str, dict[str, int]]:
    """Lee `asis_outbox` de cada colegio y genera mensajes + push."""
    resumen: dict[str, dict[str, int]] = {}
    for tenant_id in settings.SCHOOL_TENANTS:
        if not circuit_breaker.permite_intentar(tenant_id):
            logger.info("poller_salta_circuito_abierto", extra={"tenant": tenant_id})
            continue
        try:
            resumen[tenant_id] = procesar_lote_tenant(tenant_id)
            circuit_breaker.registrar_exito(tenant_id)
        except Exception:  # noqa: BLE001
            circuit_breaker.registrar_fallo(tenant_id)
            logger.exception("poller_tenant_error", extra={"tenant": tenant_id})
            resumen[tenant_id] = {"leidos": 0, "creados": 0, "errores": 1}
    return resumen
