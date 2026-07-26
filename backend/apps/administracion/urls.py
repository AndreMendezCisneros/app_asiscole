"""Rutas de administración y sistema."""

from __future__ import annotations

from django.urls import path

from apps.administracion import views

urlpatterns = [
    path("feature-flags", views.FeatureFlagsView.as_view(), name="feature-flags"),
    path("admin/apoderados", views.ApoderadosAdminView.as_view(), name="admin-apoderados"),
    path(
        "admin/apoderados/<int:id>/suspender",
        views.SuspenderView.as_view(),
        name="admin-suspender",
    ),
    path(
        "admin/apoderados/<int:id>/reactivar",
        views.ReactivarView.as_view(),
        name="admin-reactivar",
    ),
    path(
        "admin/apoderados/<int:id>/cerrar-sesion",
        views.CerrarSesionView.as_view(),
        name="admin-cerrar-sesion",
    ),
    path("admin/avisos", views.AvisosView.as_view(), name="admin-avisos"),
]
