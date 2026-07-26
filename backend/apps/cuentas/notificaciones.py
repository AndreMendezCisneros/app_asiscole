"""Notificaciones push de la app `cuentas` (intento de acceso, transferencia, suspensión)."""

from __future__ import annotations

import logging
import uuid

from apps.cuentas.models import Apoderado, PushToken, TransferenciaSesion
from apps.mensajeria.push.base import MensajePush
from apps.mensajeria.push.facade import ServicioPush

logger = logging.getLogger("asiscole.cuentas.push")


def _tokens_activos(apoderado: Apoderado, device_id: str | None = None) -> list[PushToken]:
    consulta = PushToken.objects.filter(apoderado=apoderado, activo=True)
    if device_id:
        consulta = consulta.filter(device_id=device_id)
    return list(consulta)


def _enviar(tokens: list[PushToken], tipo: str, destino: str) -> bool:
    if not tokens:
        return False
    carga = MensajePush(message_id=str(uuid.uuid4()), tipo=tipo, destino=destino)
    try:
        ServicioPush().enviar(tokens, carga, idempotente=True)
        return True
    except Exception:  # noqa: BLE001
        logger.warning("push_cuentas_error", extra={"tipo": tipo, "destinos": len(tokens)})
        return False


def notificar_intento_acceso(apoderado: Apoderado, device_id_intento: str) -> bool:
    """Avisa al dispositivo con sesión viva de un intento de acceso (ADR-07)."""
    try:
        destinos = _tokens_activos(apoderado)
        ok = _enviar(destinos, "intento_acceso", "sesion/alerta")
        logger.info(
            "push_intento_acceso",
            extra={
                "apoderado_id": apoderado.pk,
                "device_id_intento": device_id_intento,
                "destinos": len(destinos),
                "enviado": ok,
            },
        )
        return ok
    except Exception:  # noqa: BLE001
        logger.warning("push_intento_acceso_error", extra={"apoderado_id": apoderado.pk})
        return False


def notificar_solicitud_transferencia(
    apoderado: Apoderado, transferencia: TransferenciaSesion
) -> bool:
    """Pide al dispositivo activo que apruebe o rechace un traspaso (RF-A09)."""
    try:
        destinos = _tokens_activos(apoderado, transferencia.from_device_id) or _tokens_activos(
            apoderado
        )
        ok = _enviar(
            destinos,
            "session_transfer_request",
            f"transferencia/{transferencia.pk}",
        )
        logger.info(
            "push_solicitud_transferencia",
            extra={
                "apoderado_id": apoderado.pk,
                "transferencia_id": transferencia.pk,
                "destinos": len(destinos),
                "enviado": ok,
            },
        )
        return ok
    except Exception:  # noqa: BLE001
        logger.warning(
            "push_solicitud_transferencia_error", extra={"apoderado_id": apoderado.pk}
        )
        return False


def notificar_suspension(apoderado: Apoderado) -> bool:
    """Avisa al apoderado de que su cuenta fue suspendida (RF-J02)."""
    try:
        destinos = _tokens_activos(apoderado)
        ok = _enviar(destinos, "suspension", "cuenta/suspendida")
        logger.info(
            "push_suspension",
            extra={"apoderado_id": apoderado.pk, "destinos": len(destinos), "enviado": ok},
        )
        return ok
    except Exception:  # noqa: BLE001
        logger.warning("push_suspension_error", extra={"apoderado_id": apoderado.pk})
        return False
