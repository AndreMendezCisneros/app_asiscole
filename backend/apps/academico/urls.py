"""Rutas académicas."""

from __future__ import annotations

from django.urls import path

from apps.academico import views

urlpatterns = [
    path("asistencias", views.AsistenciasView.as_view(), name="asistencias"),
    path("incidencias", views.IncidenciasView.as_view(), name="incidencias"),
    path("incidencias/<int:id>", views.IncidenciaDetalleView.as_view(), name="incidencia-detalle"),
]
