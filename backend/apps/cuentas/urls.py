"""Rutas de `cuentas`, exactamente las declaradas en `docs/openapi.yaml`.

El prefijo `/v0.1/` lo pone `config/urls.py`, asi que aqui las rutas empiezan en
`auth/`.

El id de transferencia es BIGSERIAL en `asis_transferencia_sesion`. La ruta lo
acepta como entero; el contrato OpenAPI y las respuestas JSON lo exponen como
cadena (p. ej. `"42"`).
"""

from __future__ import annotations

from django.urls import path

from apps.cuentas import perfil_views, views

urlpatterns = [
    path("perfil", perfil_views.PerfilView.as_view(), name="perfil"),
    path("perfil/estudiantes", perfil_views.EstudiantesView.as_view(), name="perfil-estudiantes"),
    path(
        "perfil/estudiantes/vincular",
        perfil_views.VincularEstudianteView.as_view(),
        name="perfil-vincular",
    ),
    path("perfil/push-token", perfil_views.PushTokenView.as_view(), name="perfil-push-token"),
    path(
        "perfil/eliminar-cuenta",
        perfil_views.EliminarCuentaView.as_view(),
        name="perfil-eliminar-cuenta",
    ),
    path("auth/login", views.LoginView.as_view(), name="auth-login"),
    path("auth/refresh-data", views.RefreshDataView.as_view(), name="auth-refresh-data"),
    path("auth/renew-session", views.RenewSessionView.as_view(), name="auth-renew-session"),
    path("auth/logout", views.LogoutView.as_view(), name="auth-logout"),
    path(
        "auth/session-transfer/request",
        views.SolicitarTransferenciaView.as_view(),
        name="auth-session-transfer-request",
    ),
    path(
        "auth/session-transfer/<int:id>/approve",
        views.AprobarTransferenciaView.as_view(),
        name="auth-session-transfer-approve",
    ),
    path(
        "auth/session-transfer/<int:id>/reject",
        views.RechazarTransferenciaView.as_view(),
        name="auth-session-transfer-reject",
    ),
    path(
        "auth/session-transfer/<int:id>",
        views.ConsultarTransferenciaView.as_view(),
        name="auth-session-transfer-detail",
    ),
    path("auth/admin/login", views.AdminLoginView.as_view(), name="auth-admin-login"),
]
