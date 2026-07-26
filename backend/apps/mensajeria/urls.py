"""Rutas de mensajería."""

from __future__ import annotations

from django.urls import path

from apps.mensajeria import views

urlpatterns = [
    path("mensajes", views.MensajesView.as_view(), name="mensajes"),
    path("mensajes/leidos", views.MensajesLeidosView.as_view(), name="mensajes-leidos"),
]
