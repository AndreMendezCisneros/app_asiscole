"""Rutas de ingesta HTTP (Asiscole → canal)."""

from __future__ import annotations

from django.urls import path

from apps.ingesta.views import EventoIngestaView

urlpatterns = [
    path("ingesta/eventos", EventoIngestaView.as_view(), name="ingesta-eventos"),
]
