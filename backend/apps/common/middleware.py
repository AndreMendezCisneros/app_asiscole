"""Middlewares transversales del canal Asiscole."""

from __future__ import annotations

import re
import uuid
from collections.abc import Callable

from django.http import HttpRequest, HttpResponse

from apps.common.logging import reset_request_id, set_request_id

CABECERA_REQUEST_ID = "X-Request-Id"

#: Solo se acepta un identificador simple; asi un cliente no puede inyectar
#: saltos de linea ni comillas dentro de los logs JSON.
_REQUEST_ID_VALIDO = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def _nuevo_request_id() -> str:
    """Genera un identificador de peticion sin guiones."""
    return uuid.uuid4().hex


class RequestIdMiddleware:
    """Propaga o genera el `X-Request-Id` de cada peticion.

    Deja el valor en `request.request_id`, en el contexto de logging (para que
    el formatter JSON lo emita) y en la cabecera de la respuesta, de modo que el
    soporte pueda correlacionar un incidente sin manejar datos personales.
    """

    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        recibido = request.headers.get(CABECERA_REQUEST_ID, "").strip()
        request_id = recibido if _REQUEST_ID_VALIDO.match(recibido) else _nuevo_request_id()

        request.request_id = request_id
        token = set_request_id(request_id)
        try:
            respuesta = self.get_response(request)
        finally:
            reset_request_id(token)

        respuesta[CABECERA_REQUEST_ID] = request_id
        return respuesta
