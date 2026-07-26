"""Permiso para el endpoint de ingesta HTTP."""

from __future__ import annotations

from rest_framework.permissions import BasePermission


class EsIngestAutenticado(BasePermission):
    """La vista ya pasó `IngestApiKeyAuthentication`."""

    def has_permission(self, request, view) -> bool:
        return getattr(request, "ingest_autenticado", False) is True
