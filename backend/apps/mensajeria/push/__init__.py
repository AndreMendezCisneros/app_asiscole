"""Envio de notificaciones push del canal.

El payload es minimo a proposito (tipo, `message_id` y deep-link): el contenido
del mensaje nunca atraviesa la infraestructura de FCM ni de APNs. Ver
`apps.mensajeria.push.base` para la justificacion completa.
"""

from apps.mensajeria.push.base import (
    ErrorDeProveedorPush,
    MensajePush,
    ProveedorPush,
    ResultadoEnvio,
)
from apps.mensajeria.push.facade import ServicioPush, reiniciar_servicio_push, servicio_push

__all__ = [
    "ErrorDeProveedorPush",
    "MensajePush",
    "ProveedorPush",
    "ResultadoEnvio",
    "ServicioPush",
    "reiniciar_servicio_push",
    "servicio_push",
]
