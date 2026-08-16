"""Tareas Celery de mensajería: push y purga de retención."""

from __future__ import annotations

import logging

from celery import shared_task
from django.utils import timezone

from apps.cuentas.models import Apoderado, PushToken
from apps.mensajeria.models import TEXTO_ANONIMIZADO, Mensaje
from apps.mensajeria.push.base import MensajePush
from apps.mensajeria.push.facade import ServicioPush

logger = logging.getLogger("asiscole.mensajeria")

#: Tope al recuperar pendientes cuando el dispositivo recién registra token.
MAX_REINTENTO_PENDIENTES = 30


@shared_task(
    name="apps.mensajeria.tasks.enviar_push_mensaje",
    ignore_result=True,
    autoretry_for=(Exception,),
    retry_backoff=True,
    max_retries=5,
)
def enviar_push_mensaje(mensaje_id: str) -> bool:
    """Envía push mínimo (sin datos del menor) al dispositivo del apoderado."""
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
        resultado = ServicioPush().enviar(tokens, carga)
        if resultado.hubo_entrega:
            mensaje.marcar_entregado()
            return True
        return False
    except Exception:  # noqa: BLE001
        logger.warning(
            "push_envio_fallido",
            extra={"mensaje_id": mensaje_id, "apoderado_id": mensaje.apoderado_id},
        )
        raise


@shared_task(
    name="apps.mensajeria.tasks.enviar_push_seccion",
    ignore_result=True,
    autoretry_for=(Exception,),
    retry_backoff=True,
    max_retries=5,
)
def enviar_push_seccion(
    apoderado_id: int, message_id: str, tipo: str, destino: str
) -> bool:
    """Push genérico hacia una sección (p. ej. Notas), sin fila de bandeja."""
    try:
        apoderado = Apoderado.objects.get(pk=apoderado_id)
    except Apoderado.DoesNotExist:
        logger.info("push_seccion_apoderado_inexistente", extra={"apoderado_id": apoderado_id})
        return False

    tokens = list(PushToken.objects.filter(apoderado=apoderado, activo=True))
    if not tokens:
        logger.info(
            "push_seccion_sin_destinos",
            extra={"apoderado_id": apoderado_id, "tipo": tipo},
        )
        return False

    carga = MensajePush(message_id=message_id, tipo=tipo, destino=destino)
    try:
        resultado = ServicioPush().enviar(tokens, carga)
        return resultado.hubo_entrega
    except Exception:  # noqa: BLE001
        logger.warning(
            "push_seccion_fallido",
            extra={"apoderado_id": apoderado_id, "tipo": tipo},
        )
        raise


def reintentar_push_pendientes(
    apoderado: Apoderado, *, limite: int = MAX_REINTENTO_PENDIENTES
) -> int:
    """Reenvía push de mensajes aún no entregados (p. ej. tras registrar token)."""
    if not PushToken.objects.filter(apoderado=apoderado, activo=True).exists():
        return 0

    pendientes = list(
        Mensaje.objects.filter(apoderado=apoderado, entregado=False)
        .order_by("-emitido_en")[: max(1, min(int(limite), MAX_REINTENTO_PENDIENTES))]
    )
    enviados = 0
    for mensaje in pendientes:
        try:
            if enviar_push_mensaje(str(mensaje.pk)):
                enviados += 1
        except Exception:  # noqa: BLE001 — un mensaje no tumba el lote
            logger.warning(
                "push_reintento_fallido",
                extra={"mensaje_id": str(mensaje.pk), "apoderado_id": apoderado.pk},
            )
    if pendientes:
        logger.info(
            "push_reintento_pendientes",
            extra={
                "apoderado_id": apoderado.pk,
                "pendientes": len(pendientes),
                "enviados": enviados,
            },
        )
    return enviados


@shared_task(
    name="apps.mensajeria.tasks.reintentar_push_pendientes_task",
    ignore_result=True,
)
def reintentar_push_pendientes_task(
    apoderado_id: int, limite: int = MAX_REINTENTO_PENDIENTES
) -> int:
    """Variante Celery: no bloquea el request de login/registro de token."""
    try:
        apoderado = Apoderado.objects.get(pk=apoderado_id)
    except Apoderado.DoesNotExist:
        return 0
    return reintentar_push_pendientes(apoderado, limite=limite)


def encolar_reintento_push_pendientes(apoderado_id: int) -> None:
    """Encola el reintento; si Celery/broker no está, ejecuta en proceso."""
    try:
        reintentar_push_pendientes_task.delay(apoderado_id)
    except Exception:  # noqa: BLE001 — degradación: no tumbar login
        logger.warning(
            "push_reintento_encola_fallo",
            extra={"apoderado_id": apoderado_id},
        )
        try:
            reintentar_push_pendientes_task(apoderado_id)
        except Exception:  # noqa: BLE001
            logger.warning(
                "push_reintento_sync_fallo",
                extra={"apoderado_id": apoderado_id},
            )


@shared_task(name="apps.mensajeria.tasks.purgar_mensajes_vencidos", ignore_result=True)
def purgar_mensajes_vencidos() -> dict[str, int]:
    """Anonimiza mensajes que superaron MESSAGE_RETENTION_MONTHS (RNF-11)."""
    ahora = timezone.now()
    qs = Mensaje.objects.filter(retenido_hasta__lte=ahora).exclude(texto=TEXTO_ANONIMIZADO)
    total = qs.update(texto=TEXTO_ANONIMIZADO, metadata={})
    logger.info("purga_retencion", extra={"anonimizados": total})
    return {"anonimizados": total}
