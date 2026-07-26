"""Ingesta HTTP: Asiscole empuja un evento y el canal crea mensajes."""

from __future__ import annotations

import logging
from typing import Any

from django.conf import settings

from apps.common.errors import ValidationError
from apps.ingesta.services import crear_mensajes_desde_evento
from apps.mensajeria.plantillas.base import ErrorDePlantilla

logger = logging.getLogger("asiscole.ingesta")

TIPOS_PERMITIDOS = frozenset({"entrada", "salida", "incidencia"})


def recibir_evento(
    *,
    tenant_id: str,
    tipo: str,
    id_estudiante: int,
    id_registro: int,
    payload: dict[str, Any] | None,
) -> dict[str, Any]:
    """Crea mensajes para los apoderados vinculados y dispara push.

    Returns:
        Contadores y `origen_evento` para la respuesta 202.
    """
    tenant_id = (tenant_id or "").strip()
    tipo = (tipo or "").strip().lower()

    if not tenant_id:
        raise ValidationError("Falta tenant_id.")
    if tenant_id not in settings.SCHOOL_TENANTS:
        raise ValidationError("El colegio indicado no está configurado en el canal.")
    if tipo not in TIPOS_PERMITIDOS:
        raise ValidationError("tipo debe ser entrada, salida o incidencia.")
    if id_estudiante is None or int(id_estudiante) <= 0:
        raise ValidationError("id_estudiante inválido.")
    if id_registro is None or int(id_registro) <= 0:
        raise ValidationError("id_registro inválido.")

    payload = dict(payload or {})
    # El destinatario se resuelve por directorio; nunca aceptar estos campos.
    payload.pop("telefono_contacto", None)
    payload.pop("codigo_barras", None)
    payload.setdefault("id_estudiante", int(id_estudiante))

    try:
        creados = crear_mensajes_desde_evento(
            tenant_id=tenant_id,
            tipo=tipo,
            id_estudiante=int(id_estudiante),
            id_registro=int(id_registro),
            payload=payload,
        )
    except ErrorDePlantilla as exc:
        raise ValidationError("El payload del evento está incompleto o es inválido.") from exc

    from apps.mensajeria.tasks import enviar_push_mensaje

    for mensaje in creados:
        # Sin depender de Redis/Celery en el camino HTTP (útil en local).
        try:
            enviar_push_mensaje(str(mensaje.pk))
        except Exception:  # noqa: BLE001
            logger.warning(
                "push_ingesta_http_fallido",
                extra={"mensaje_id": str(mensaje.pk)},
            )

    origen = f"{tipo}:{int(id_registro)}"
    logger.info(
        "ingesta_http_ok",
        extra={
            "tenant": tenant_id,
            "tipo": tipo,
            "id_registro": int(id_registro),
            "creados": len(creados),
        },
    )
    return {
        "creados": len(creados),
        "origen_evento": origen,
        "apoderados_notificados": len(creados),
    }
