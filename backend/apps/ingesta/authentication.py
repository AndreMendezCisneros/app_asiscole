"""Autenticación por clave compartida para la ingesta HTTP desde Asiscole."""

from __future__ import annotations

from django.conf import settings
from rest_framework.authentication import BaseAuthentication
from rest_framework.request import Request

from apps.common.errors import Unauthenticated

CABECERA_INGEST = "HTTP_X_ASISCOLE_INGEST_KEY"


class IngestApiKeyAuthentication(BaseAuthentication):
    """Valida `X-Asiscole-Ingest-Key` contra `settings.INGEST_API_KEY`."""

    def authenticate(self, request: Request):
        esperado = (settings.INGEST_API_KEY or "").strip()
        if not esperado:
            raise Unauthenticated("La ingesta por API no está configurada.")

        recibido = (request.META.get(CABECERA_INGEST) or "").strip()
        if not recibido or recibido != esperado:
            raise Unauthenticated("Clave de ingesta inválida.")

        # DRF espera (user, auth). No hay usuario Django; marcamos el request.
        request.ingest_autenticado = True  # type: ignore[attr-defined]
        return (None, "ingest_api_key")
