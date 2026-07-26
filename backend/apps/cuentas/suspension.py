"""Suspension, reactivacion y cierre forzado de cuentas (RF-J01 a RF-J04).

Son las tres palancas del administrador sobre una cuenta del canal. Todas dejan
rastro en `asis_auditoria` con datos exclusivamente tecnicos: quien, que accion
y sobre que identificador interno, jamas el telefono ni datos del estudiante.

El efecto de la suspension es inmediato porque las sesiones se revocan en la BD:
los tokens ya emitidos dejan de servir en la siguiente peticion, sin esperar a
que caduquen.
"""

from __future__ import annotations

import logging

from django.db import transaction
from django.utils import timezone

from apps.cuentas import notificaciones
from apps.cuentas.models import (
    CUENTA_ACTIVA,
    CUENTA_SUSPENDIDA,
    SESION_ACTIVA,
    SESION_REVOCADA,
    Apoderado,
    Auditoria,
    PushToken,
    SesionActiva,
)

logger = logging.getLogger("asiscole.cuentas.suspension")


def registrar_auditoria(
    accion: str,
    *,
    apoderado: Apoderado | None = None,
    actor: str | None = None,
    detalle: dict | None = None,
    request_id: str | None = None,
) -> Auditoria:
    """Escribe una entrada en `asis_auditoria`.

    Args:
        accion: Verbo tecnico, por ejemplo `cuenta_suspendida`.
        apoderado: Cuenta afectada.
        actor: Quien ejecuto la accion (identidad del administrador).
        detalle: Metadatos tecnicos. No debe llevar datos personales.
        request_id: Correlacion con el log de la peticion.
    """
    return Auditoria.objects.create(
        apoderado=apoderado,
        actor=actor,
        accion=accion,
        detalle=detalle or {},
        request_id=request_id,
    )


def _revocar_sesiones(apoderado: Apoderado) -> int:
    """Revoca todas las sesiones activas de la cuenta.

    Returns:
        Cuantas sesiones se cerraron.
    """
    return SesionActiva.objects.filter(apoderado=apoderado, estado=SESION_ACTIVA).update(
        estado=SESION_REVOCADA, ultima_actividad_en=timezone.now()
    )


def suspender(
    apoderado: Apoderado,
    motivo: str,
    *,
    actor: str | None = None,
    notificar_push: bool = True,
    request_id: str | None = None,
) -> Apoderado:
    """Suspende una cuenta y corta su acceso al instante (RF-J01 a RF-J03).

    Args:
        apoderado: Cuenta a suspender.
        motivo: Texto que se le mostrara al apoderado en la pantalla de bloqueo.
        actor: Administrador que ejecuta la accion.
        notificar_push: Si se avisa por push al dispositivo.
        request_id: Correlacion con el log.

    Returns:
        La cuenta ya suspendida.
    """
    with transaction.atomic():
        apoderado.estado = CUENTA_SUSPENDIDA
        apoderado.motivo_suspension = motivo
        apoderado.suspendido_en = timezone.now()
        apoderado.save(update_fields=["estado", "motivo_suspension", "suspendido_en", "actualizado_en"])

        cerradas = _revocar_sesiones(apoderado)

        registrar_auditoria(
            "cuenta_suspendida",
            apoderado=apoderado,
            actor=actor,
            detalle={"sesiones_cerradas": cerradas, "notificar_push": notificar_push},
            request_id=request_id,
        )

    if notificar_push:
        # Fuera de la transaccion y sin propagar fallos: el push no puede
        # deshacer una suspension ya escrita.
        notificaciones.notificar_suspension(apoderado)

    logger.info(
        "cuenta_suspendida",
        extra={"apoderado_id": apoderado.pk, "sesiones_cerradas": cerradas},
    )
    return apoderado


def reactivar(
    apoderado: Apoderado, *, actor: str | None = None, request_id: str | None = None
) -> Apoderado:
    """Reactiva una cuenta suspendida (RF-J04).

    La sesion anterior nunca se restaura: el apoderado vuelve a iniciar sesion.
    """
    with transaction.atomic():
        apoderado.estado = CUENTA_ACTIVA
        apoderado.motivo_suspension = None
        apoderado.suspendido_en = None
        apoderado.save(update_fields=["estado", "motivo_suspension", "suspendido_en", "actualizado_en"])

        registrar_auditoria(
            "cuenta_reactivada", apoderado=apoderado, actor=actor, request_id=request_id
        )

    logger.info("cuenta_reactivada", extra={"apoderado_id": apoderado.pk})
    return apoderado


def forzar_cierre_sesion(
    apoderado: Apoderado, *, actor: str | None = None, request_id: str | None = None
) -> int:
    """Cierra la sesion activa de una cuenta sin suspenderla (RF-B04).

    Es la via de escape cuando el apoderado perdio el dispositivo y no puede
    aprobar una transferencia (ADR-06).

    Returns:
        Cuantas sesiones se cerraron.
    """
    with transaction.atomic():
        cerradas = _revocar_sesiones(apoderado)
        PushToken.objects.filter(apoderado=apoderado).update(activo=False)
        registrar_auditoria(
            "sesion_cerrada_por_admin",
            apoderado=apoderado,
            actor=actor,
            detalle={"sesiones_cerradas": cerradas},
            request_id=request_id,
        )

    logger.info(
        "sesion_cerrada_por_admin",
        extra={"apoderado_id": apoderado.pk, "sesiones_cerradas": cerradas},
    )
    return cerradas
