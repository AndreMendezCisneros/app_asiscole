"""Procesamiento de eventos del outbox del colegio hacia mensajes del canal."""

from __future__ import annotations

import json
import logging
from typing import Any

from django.conf import settings
from django.db import IntegrityError, connections, transaction
from django.utils import timezone

from apps.cuentas.models import CUENTA_ACTIVA, Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from apps.mensajeria.models import Mensaje
from apps.mensajeria.plantillas.base import ContextoEvento, ErrorDePlantilla
from apps.mensajeria.plantillas.registry import renderizar
from config.db_router import tenant_alias

logger = logging.getLogger("asiscole.ingesta")

LOTE_OUTBOX = 100


def _nombre_colegio(tenant_id: str) -> str:
    return settings.SCHOOL_TENANTS.get(tenant_id, tenant_id)


def _payload_como_dict(payload: Any) -> dict[str, Any]:
    """Normaliza el JSONB del outbox a dict.

    Con el cursor crudo de Django/psycopg el JSONB a veces llega como `str`.
    `dict("...")` interpreta caracteres y revienta; aquí se hace `json.loads`.
    """
    if payload is None:
        return {}
    if isinstance(payload, dict):
        return payload
    if isinstance(payload, (bytes, bytearray, memoryview)):
        payload = bytes(payload).decode("utf-8")
    if isinstance(payload, str):
        texto = payload.strip()
        if not texto:
            return {}
        cargado = json.loads(texto)
        if not isinstance(cargado, dict):
            raise TypeError("payload_outbox_no_objeto")
        return cargado
    raise TypeError(f"payload_outbox_tipo_{type(payload).__name__}")


def _apoderados_destino(tenant_id: str, id_estudiante: int) -> list[Apoderado]:
    """Apoderados activos vinculados al estudiante en el directorio."""
    telefonos = (
        Directorio.objects.filter(
            tenant_id=tenant_id,
            id_estudiante=id_estudiante,
            estado_vinculo=VINCULO_ACTIVO,
        )
        .values_list("telefono", flat=True)
        .distinct()
    )
    if not telefonos:
        return []
    return list(Apoderado.objects.filter(telefono__in=list(telefonos), estado=CUENTA_ACTIVA))


def crear_mensajes_desde_evento(
    *,
    tenant_id: str,
    tipo: str,
    id_estudiante: int,
    id_registro: int,
    payload: dict[str, Any],
) -> list[Mensaje]:
    """Genera mensajes idempotentes para todos los apoderados del estudiante.

    Returns:
        Mensajes recién creados (vacío si no hay destinatarios o ya existían).
    """
    origen = f"{tipo}:{id_registro}"
    ctx = ContextoEvento.desde_payload(
        tipo,
        tenant_id,
        payload,
        colegio=_nombre_colegio(tenant_id),
        id_registro=id_registro,
    )
    try:
        texto = renderizar(tipo, ctx)
    except ErrorDePlantilla:
        logger.warning(
            "plantilla_fallo",
            extra={"tenant": tenant_id, "tipo": tipo, "id_registro": id_registro},
        )
        raise

    metadata = ctx.metadata()
    creados: list[Mensaje] = []
    for apoderado in _apoderados_destino(tenant_id, id_estudiante):
        try:
            with transaction.atomic():
                mensaje = Mensaje.objects.create(
                    apoderado=apoderado,
                    tenant_id=tenant_id,
                    id_estudiante=id_estudiante,
                    tipo=tipo,
                    texto=texto,
                    metadata=metadata,
                    origen_evento=origen,
                )
            creados.append(mensaje)
        except IntegrityError:
            # Idempotencia: el mismo origen ya se notificó a esta cuenta.
            logger.info(
                "mensaje_duplicado_omitido",
                extra={
                    "tenant": tenant_id,
                    "tipo": tipo,
                    "id_registro": id_registro,
                    "apoderado_id": apoderado.pk,
                },
            )
    return creados


def marcar_procesado(tenant_id: str, outbox_id: int) -> None:
    """Marca la fila del outbox como procesada en la BD del colegio."""
    alias = tenant_alias(tenant_id)
    with connections[alias].cursor() as cursor:
        cursor.execute(
            """
            UPDATE public.asis_outbox
               SET procesado = true,
                   procesado_en = now(),
                   ultimo_error = NULL
             WHERE id = %s
            """,
            [outbox_id],
        )


def marcar_error(tenant_id: str, outbox_id: int, codigo_error: str) -> None:
    """Incrementa intentos y guarda un código técnico (sin datos personales)."""
    alias = tenant_alias(tenant_id)
    with connections[alias].cursor() as cursor:
        cursor.execute(
            """
            UPDATE public.asis_outbox
               SET intentos = coalesce(intentos, 0) + 1,
                   ultimo_error = %s
             WHERE id = %s
            """,
            [codigo_error[:200], outbox_id],
        )


def leer_pendientes(tenant_id: str, limite: int = LOTE_OUTBOX) -> list[dict[str, Any]]:
    """Lee filas pendientes del outbox del colegio."""
    alias = tenant_alias(tenant_id)
    with connections[alias].cursor() as cursor:
        cursor.execute(
            """
            SELECT id, tipo, id_estudiante, id_registro, payload, intentos
              FROM public.asis_outbox
             WHERE procesado = false
             ORDER BY id ASC
             LIMIT %s
            """,
            [limite],
        )
        columnas = [col[0] for col in cursor.description]
        return [dict(zip(columnas, fila, strict=True)) for fila in cursor.fetchall()]


def procesar_lote_tenant(tenant_id: str) -> dict[str, int]:
    """Procesa un lote de outbox de un colegio.

    Returns:
        Contadores: leidos, creados, errores, omitidos.
    """
    from apps.mensajeria.tasks import enviar_push_mensaje

    filas = leer_pendientes(tenant_id)
    creados = 0
    errores = 0
    for fila in filas:
        outbox_id = int(fila["id"])
        try:
            tipo_evento = str(fila["tipo"] or "").strip().lower()
            if tipo_evento == "nota":
                from apps.mensajeria.notas import upsert_nota
                from apps.mensajeria.tasks import enviar_push_seccion

                nota, created = upsert_nota(
                    tenant_id=tenant_id,
                    id_estudiante=int(fila["id_estudiante"]),
                    id_registro=int(fila["id_registro"]),
                    payload=_payload_como_dict(fila["payload"]),
                )
                if created:
                    creados += 1
                    for apoderado in _apoderados_destino(
                        tenant_id, int(fila["id_estudiante"])
                    ):
                        try:
                            enviar_push_seccion.delay(
                                apoderado.pk,
                                str(nota.pk),
                                "nota",
                                f"notas/{nota.pk}",
                            )
                        except Exception:  # noqa: BLE001
                            logger.warning(
                                "push_enqueue_nota_fallido",
                                extra={"tenant": tenant_id, "nota_id": str(nota.pk)},
                            )
                marcar_procesado(tenant_id, outbox_id)
                continue

            mensajes = crear_mensajes_desde_evento(
                tenant_id=tenant_id,
                tipo=tipo_evento,
                id_estudiante=int(fila["id_estudiante"]),
                id_registro=int(fila["id_registro"]),
                payload=_payload_como_dict(fila["payload"]),
            )
            for mensaje in mensajes:
                # Sin Redis/Celery el .delay no debe tumbar el lote: el mensaje
                # ya está en BD y la bandeja puede leerlo; el push es best-effort.
                try:
                    enviar_push_mensaje.delay(str(mensaje.pk))
                except Exception:  # noqa: BLE001
                    logger.warning(
                        "push_enqueue_fallido",
                        extra={"tenant": tenant_id, "mensaje_id": str(mensaje.pk)},
                    )
                creados += 1
            marcar_procesado(tenant_id, outbox_id)
        except Exception:  # noqa: BLE001 — el poller no debe morir por un evento
            errores += 1
            marcar_error(tenant_id, outbox_id, "PROCESAMIENTO_FALLIDO")
            logger.exception(
                "outbox_evento_error",
                extra={"tenant": tenant_id, "outbox_id": outbox_id},
            )
    if filas:
        from apps.ingesta.models import CursorIngesta

        ultimo = max(int(f["id"]) for f in filas)
        CursorIngesta.objects.update_or_create(
            tenant_id=tenant_id,
            defaults={"ultimo_id": ultimo, "actualizado_en": timezone.now()},
        )
    return {"leidos": len(filas), "creados": creados, "errores": errores}
