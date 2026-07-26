"""Paginacion por cursor de la bandeja de mensajes (RF-D06).

La bandeja se lee de mas reciente a mas antiguo y se sincroniza en dos modos:

* `since=<ISO-8601>`: trae solo lo emitido despues de esa marca. Es el modo que
  usa la app al volver de segundo plano o al recuperar la conexion.
* `cursor=<opaco>`: continua el listado donde termino la pagina anterior, para
  el scroll infinito hacia atras.

El cursor es opaco a proposito (base64 de la marca de tiempo y el id): el cliente
no debe construirlo ni interpretarlo, solo devolverlo tal cual.
"""

from __future__ import annotations

import base64
import binascii
import json
from collections import OrderedDict

from django.db.models import Q
from django.utils.dateparse import parse_datetime
from django.utils.timezone import is_naive, make_aware
from rest_framework.pagination import BasePagination
from rest_framework.response import Response

from apps.common.errors import ValidationError


def _codificar_cursor(marca, identificador) -> str:
    """Empaqueta (fecha, id) en un texto opaco seguro para URL."""
    crudo = json.dumps({"t": marca.isoformat(), "i": identificador}, separators=(",", ":"))
    return base64.urlsafe_b64encode(crudo.encode("utf-8")).decode("ascii").rstrip("=")


def _decodificar_cursor(valor: str) -> tuple:
    """Deshace `_codificar_cursor`.

    Raises:
        ValidationError: Si el cursor no es legible. No se filtra el motivo
            exacto para no dar pistas sobre el formato interno.
    """
    try:
        relleno = "=" * (-len(valor) % 4)
        crudo = base64.urlsafe_b64decode(valor + relleno).decode("utf-8")
        datos = json.loads(crudo)
        marca = parse_datetime(datos["t"])
        identificador = datos["i"]
    except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
        raise ValidationError() from exc
    if marca is None:
        raise ValidationError()
    return _con_zona(marca), identificador


def _con_zona(marca):
    """Asume la zona horaria activa (America/Lima) si la marca viene naive."""
    return make_aware(marca) if is_naive(marca) else marca


class CursorMensajesPagination(BasePagination):
    """Paginacion descendente por (fecha, id) con soporte de `since`.

    La vista de mensajeria puede sobrescribir `campo_fecha` y `campo_id` si el
    modelo final usa otros nombres de columna.
    """

    campo_fecha = "creado_en"
    campo_id = "id"

    parametro_cursor = "cursor"
    parametro_since = "since"
    parametro_limite = "limit"

    tamano_por_defecto = 50
    tamano_maximo = 100

    def __init__(self) -> None:
        self.hay_mas = False
        self.cursor_siguiente: str | None = None
        self.pagina: list = []

    def _limite(self, request) -> int:
        """Lee `limit` de la query string y lo acota al maximo permitido."""
        crudo = request.query_params.get(self.parametro_limite)
        if crudo is None or crudo == "":
            return self.tamano_por_defecto
        try:
            valor = int(crudo)
        except (TypeError, ValueError) as exc:
            raise ValidationError() from exc
        if valor < 1:
            raise ValidationError()
        return min(valor, self.tamano_maximo)

    def paginate_queryset(self, queryset, request, view=None):
        """Aplica `since` y `cursor` y devuelve la pagina como lista."""
        limite = self._limite(request)

        since_crudo = request.query_params.get(self.parametro_since)
        if since_crudo:
            marca = parse_datetime(since_crudo)
            if marca is None:
                raise ValidationError()
            queryset = queryset.filter(**{f"{self.campo_fecha}__gt": _con_zona(marca)})

        cursor_crudo = request.query_params.get(self.parametro_cursor)
        if cursor_crudo:
            marca, identificador = _decodificar_cursor(cursor_crudo)
            queryset = queryset.filter(
                Q(**{f"{self.campo_fecha}__lt": marca})
                | Q(**{self.campo_fecha: marca, f"{self.campo_id}__lt": identificador})
            )

        queryset = queryset.order_by(f"-{self.campo_fecha}", f"-{self.campo_id}")

        # Se pide un elemento de mas para saber si queda cola, sin hacer COUNT.
        filas = list(queryset[: limite + 1])
        self.hay_mas = len(filas) > limite
        self.pagina = filas[:limite]

        if self.hay_mas and self.pagina:
            ultimo = self.pagina[-1]
            self.cursor_siguiente = _codificar_cursor(
                getattr(ultimo, self.campo_fecha), getattr(ultimo, self.campo_id)
            )
        else:
            self.cursor_siguiente = None

        return self.pagina

    def get_paginated_response(self, data) -> Response:
        """Envuelve la pagina en el sobre que espera la app."""
        return Response(
            OrderedDict(
                [
                    ("items", data),
                    ("next_cursor", self.cursor_siguiente),
                    ("has_more", self.hay_mas),
                ]
            )
        )

    def get_paginated_response_schema(self, schema) -> dict:
        """Describe el sobre de la respuesta para drf-spectacular."""
        return {
            "type": "object",
            "required": ["items", "has_more"],
            "properties": {
                "items": schema,
                "next_cursor": {"type": "string", "nullable": True},
                "has_more": {"type": "boolean"},
            },
        }

    def get_schema_operation_parameters(self, view) -> list[dict]:
        """Documenta `since`, `cursor` y `limit` en el OpenAPI."""
        return [
            {
                "name": self.parametro_since,
                "required": False,
                "in": "query",
                "description": "Marca ISO-8601. Devuelve solo lo emitido despues de ella.",
                "schema": {"type": "string", "format": "date-time"},
            },
            {
                "name": self.parametro_cursor,
                "required": False,
                "in": "query",
                "description": "Cursor opaco devuelto en `next_cursor`.",
                "schema": {"type": "string"},
            },
            {
                "name": self.parametro_limite,
                "required": False,
                "in": "query",
                "description": f"Tamano de pagina (maximo {self.tamano_maximo}).",
                "schema": {"type": "integer", "default": self.tamano_por_defecto},
            },
        ]
