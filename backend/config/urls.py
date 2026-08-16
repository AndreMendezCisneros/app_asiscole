"""Rutas raiz del canal Asiscole.

Todos los endpoints de negocio cuelgan de ``/v0.1/``. Contract-first: ningun
cliente consume una ruta que no este antes en ``docs/openapi.yaml``.
"""

from __future__ import annotations

from django.conf import settings
from django.http import HttpRequest, JsonResponse
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from apps.common import paginas


def health(request: HttpRequest) -> JsonResponse:
    """Sonda de vida del proceso web.

    No toca la BD ni Redis a proposito: responde si el contenedor sirve trafico.
    Incluye `fcm_disponible` (bool) para ops: no filtra rutas ni secretos.
    """
    from apps.mensajeria.push.fcm import ProveedorFCM

    fcm_ok = False
    try:
        fcm_ok = ProveedorFCM().disponible()
    except Exception:  # noqa: BLE001 — health nunca debe caer
        fcm_ok = False

    return JsonResponse(
        {
            "status": "ok",
            "servicio": "asiscole-backend",
            "fcm_disponible": fcm_ok,
        }
    )


urlpatterns = [
    path("health", health, name="health"),
    # Pagina publica: Play exige una URL web para pedir la eliminacion de cuenta,
    # ademas del boton dentro de la app. No recibe ni muestra datos personales.
    path("eliminar-cuenta", paginas.eliminar_cuenta, name="eliminar-cuenta"),
    path("v0.1/", include("apps.cuentas.urls")),
    path("v0.1/", include("apps.directorio.urls")),
    path("v0.1/", include("apps.mensajeria.urls")),
    path("v0.1/", include("apps.academico.urls")),
    path("v0.1/", include("apps.ingesta.urls")),
    path("v0.1/", include("apps.administracion.urls")),
]

# Swagger/OpenAPI solo con DEBUG=True. En producción el contrato no se sirve.
if settings.DEBUG:
    urlpatterns += [
        path("v0.1/schema/", SpectacularAPIView.as_view(), name="schema"),
        path(
            "v0.1/docs/",
            SpectacularSwaggerView.as_view(url_name="schema"),
            name="docs",
        ),
    ]
