"""Politica de versiones de la app (GET /sistema/version-app)."""

from __future__ import annotations

import pytest

from apps.administracion.models import VersionApp
from apps.administracion.services import politica_version_app
from apps.common.errors import ValidationError


@pytest.mark.django_db
def test_version_app_es_publica(api):
    r = api.get("/v0.1/sistema/version-app", {"plataforma": "android"})
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["plataforma"] == "android"
    assert cuerpo["min_soportada"] == 1
    assert cuerpo["actualizacion_obligatoria"] is False


@pytest.mark.django_db
def test_version_app_obliga_si_el_cliente_es_viejo(api):
    VersionApp.objects.update_or_create(
        plataforma="android",
        defaults={"min_soportada": 5, "ultima_disponible": 5},
    )
    r = api.get(
        "/v0.1/sistema/version-app",
        {"plataforma": "android"},
        HTTP_X_APP_VERSION="2",
    )
    assert r.status_code == 200
    assert r.json()["actualizacion_obligatoria"] is True
    assert r.json()["actualizacion_disponible"] is True


@pytest.mark.django_db
def test_version_app_sin_cabecera_no_bloquea(api):
    VersionApp.objects.update_or_create(
        plataforma="android",
        defaults={"min_soportada": 9, "ultima_disponible": 9},
    )
    r = api.get("/v0.1/sistema/version-app", {"plataforma": "android"})
    assert r.status_code == 200
    # Cliente antiguo o proxy que recorta la cabecera: no se deja a nadie fuera.
    assert r.json()["actualizacion_obligatoria"] is False


@pytest.mark.django_db
def test_version_app_ios_sembrada_sin_ficha(api):
    r = api.get("/v0.1/sistema/version-app", {"plataforma": "ios"}, HTTP_X_APP_VERSION="1")
    assert r.status_code == 200
    cuerpo = r.json()
    assert cuerpo["plataforma"] == "ios"
    assert cuerpo["actualizacion_obligatoria"] is False
    assert cuerpo["actualizacion_disponible"] is False
    # Sin ficha en la App Store no se ofrece un enlace (y nunca el de Play).
    assert cuerpo["url_tienda"] is None


@pytest.mark.django_db
def test_version_app_plataforma_invalida(api):
    r = api.get("/v0.1/sistema/version-app", {"plataforma": "windows"})
    assert r.status_code == 400
    assert r.json()["code"] == "VALIDATION_ERROR"


@pytest.mark.django_db
def test_politica_version_app_rechaza_plataforma_vacia():
    with pytest.raises(ValidationError):
        politica_version_app("", 1)
