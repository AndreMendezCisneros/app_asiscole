"""Tareas Celery de mensajería: push y purga de retención."""

from __future__ import annotations

import logging

from celery import shared_task
from django.utils import timezone

from apps.cuentas.models import PushToken
from apps.mensajeria.models import Mensaje
from apps.mensajeria.push.base import MensajePush
from apps.mensajeria.push.facade import ServicioPush

logger = logging.getLogger("asiscole.mensajeria")


@shared_task(
    name="apps.mensajeria.tasks.enviar_push_mensaje",
    ignore_result=True,
    autoretry_for=(Exception,),
    retry_backoff=True,
    max_retries=5,
)
def enviar_push_mensaje(mensaje_id: str) -> bool:
    """Envía push mínimo (sin texto) al dispositivo del apoderado."""
    try:
        mensaje = Mensaje.objects.select_related("apoderado").get(pk=mensaje_id)
    except Mensaje.DoesNotExist:
        logger.info("push_mensaje_inexistente", extra={"mensaje_id": mensaje_id})
        return False

    tokens = list(
        PushToken.objects.filter(apoderado=mensaje.apoderado, activo=True)
    )
    if not tokens:
        logger.info(
            "push_sin_destinos",
            extra={"mensaje_id": mensaje_id, "apoderado_id": mensaje.apoderado_id},
        )
        return False

    carga = MensajePush(
        message_id=str(mensaje.pk),
        tipo=mensaje.tipo,
        destino=f"mensajes/{mensaje.pk}",
    )
    try:
        ServicioPush().enviar(tokens, carga)
        mensaje.marcar_entregado()
        return True
    except Exception:  # noqa: BLE001
        logger.warning(
            "push_envio_fallido",
            extra={"mensaje_id": mensaje_id, "apoderado_id": mensaje.apoderado_id},
        )
        raise


@shared_task(name="apps.mensajeria.tasks.purgar_mensajes_vencidos", ignore_result=True)
def purgar_mensajes_vencidos() -> dict[str, int]:
    """Anonimiza mensajes que superaron MESSAGE_RETENTION_MONTHS (RNF-11)."""
    ahora = timezone.now()
    qs = Mensaje.objects.filter(retenido_hasta__lte=ahora).exclude(texto="[eliminado]")
    total = qs.update(texto="[eliminado]", metadata={})
    logger.info("purga_retencion", extra={"anonimizados": total})
    return {"anonimizados": total}
