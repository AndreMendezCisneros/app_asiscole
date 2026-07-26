"""Manejador de excepciones del API.

Cualquier excepcion que escape de una vista se convierte en el mismo cuerpo:

    {"code": "SESSION_ALREADY_ACTIVE", "message": "...", "request_id": "..."}

Asi el cliente Flutter solo necesita mirar `code` y renderizar `message`, que ya
viene redactado en espanol por el backend.
"""

from __future__ import annotations

import logging

from django.core.exceptions import PermissionDenied as DjangoPermissionDenied
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import DatabaseError, InterfaceError, OperationalError
from django.http import Http404
from rest_framework import exceptions as drf_exceptions
from rest_framework.response import Response

from apps.common import errors
from apps.common.logging import get_request_id

logger = logging.getLogger("asiscole.api")

#: Cuando la excepcion no es del catalogo, el codigo se deduce del estado HTTP.
_CODIGO_POR_ESTADO = {
    400: errors.ValidationError.code,
    401: errors.Unauthenticated.code,
    403: errors.RoleNotAllowed.code,
    # El unico 404 del contrato es la busqueda de un vinculo apoderado-estudiante.
    404: errors.StudentLinkNotFound.code,
    410: errors.SessionExpired.code,
    423: errors.AccountLocked.code,
    429: errors.TooManyRequests.code,
    503: errors.UpstreamSchoolDbUnavailable.code,
}


def _traducir(exc: Exception) -> errors.AsiscoleError:
    """Convierte una excepcion cualquiera en un error del catalogo."""
    if isinstance(exc, errors.AsiscoleError):
        return exc

    if isinstance(exc, (Http404, drf_exceptions.NotFound)):
        return errors.StudentLinkNotFound()

    if isinstance(exc, (drf_exceptions.NotAuthenticated, drf_exceptions.AuthenticationFailed)):
        return errors.Unauthenticated()

    if isinstance(exc, (drf_exceptions.PermissionDenied, DjangoPermissionDenied)):
        return errors.RoleNotAllowed()

    if isinstance(exc, drf_exceptions.Throttled):
        return errors.TooManyRequests()

    if isinstance(exc, (drf_exceptions.ValidationError, drf_exceptions.ParseError, DjangoValidationError)):
        # No se reenvia el detalle del serializador: puede contener el valor
        # rechazado, que en este dominio suele ser un telefono o un documento.
        return errors.ValidationError()

    if isinstance(exc, (OperationalError, InterfaceError)):
        # Timeout o caida de una BD (tipicamente la de un colegio, SRS 7.8).
        return errors.UpstreamSchoolDbUnavailable()

    if isinstance(exc, drf_exceptions.APIException):
        estado = int(getattr(exc, "status_code", 500))
        generico = errors.AsiscoleError()
        generico.status_code = estado
        generico.code = _CODIGO_POR_ESTADO.get(
            estado,
            errors.ValidationError.code if 400 <= estado < 500 else errors.AsiscoleError.code,
        )
        return generico

    if isinstance(exc, DatabaseError):
        return errors.UpstreamSchoolDbUnavailable()

    return errors.AsiscoleError()


def asiscole_exception_handler(exc, context) -> Response:
    """Manejador de excepciones de DRF (`EXCEPTION_HANDLER`).

    Args:
        exc: Excepcion levantada por la vista.
        context: Contexto de DRF; incluye `request` y `view`.

    Returns:
        Una `Response` con el cuerpo uniforme del canal.
    """
    error = _traducir(exc)
    request = context.get("request") if context else None
    request_id = getattr(request, "request_id", "") or get_request_id()

    vista = context.get("view") if context else None
    datos_log = {
        "codigo": error.code,
        "estado": error.status_code,
        "vista": type(vista).__name__ if vista is not None else "",
        "excepcion": type(exc).__name__,
    }

    if error.status_code >= 500:
        # Traza completa solo para fallos del servidor. Sin datos personales.
        logger.error("error_no_controlado", extra=datos_log, exc_info=exc)
    else:
        logger.info("error_de_negocio", extra=datos_log)

    return Response(
        {"code": error.code, "message": error.message, "request_id": request_id},
        status=error.status_code,
    )
