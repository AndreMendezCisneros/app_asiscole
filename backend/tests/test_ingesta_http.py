"""Pruebas del endpoint POST /ingesta/eventos."""

from __future__ import annotations

import pytest
from django.test import override_settings

from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from apps.mensajeria.models import Mensaje

CLAVE = "clave-ingesta-test"


@pytest.fixture
def apoderado_con_vinculo(db):
    apo = Apoderado.objects.create(telefono="+51911112222")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=10,
        codigo_barras="70123456",
        nombre_estudiante="Estudiante Prueba",
        grado="3",
        seccion="A",
        nivel="Primaria",
        estado_vinculo=VINCULO_ACTIVO,
    )
    return apo


def _cuerpo(**extra):
    base = {
        "tenant_id": "jean_piaget",
        "tipo": "entrada",
        "id_estudiante": 10,
        "id_registro": 9001,
        "payload": {
            "id_estudiante": 10,
            "nombre_completo": "Estudiante Prueba",
            "grado": "3",
            "seccion": "A",
            "nivel_educativo": "Primaria",
            "fecha": "2026-07-25",
            "hora_llegada": "07:45",
            "estado": "A tiempo",
        },
    }
    base.update(extra)
    return base


@pytest.mark.django_db
@override_settings(
    INGEST_API_KEY=CLAVE,
    SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"},
)
def test_ingesta_http_crea_mensaje(api, apoderado_con_vinculo):
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 202
    body = r.json()
    assert body["creados"] == 1
    assert body["origen_evento"] == "entrada:9001"
    assert Mensaje.objects.filter(apoderado=apoderado_con_vinculo).count() == 1


@pytest.mark.django_db
@override_settings(INGEST_API_KEY=CLAVE, SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
def test_ingesta_http_sin_clave_401(api, apoderado_con_vinculo):
    r = api.post("/v0.1/ingesta/eventos", _cuerpo(), format="json")
    assert r.status_code == 401
    assert r.json()["code"] == "UNAUTHENTICATED"


@pytest.mark.django_db
@override_settings(INGEST_API_KEY=CLAVE, SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
def test_ingesta_http_clave_mala_401(api, apoderado_con_vinculo):
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY="otra",
    )
    assert r.status_code == 401


@pytest.mark.django_db
@override_settings(INGEST_API_KEY=CLAVE, SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
def test_ingesta_http_tenant_desconocido_400(api, apoderado_con_vinculo):
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(tenant_id="otro_colegio"),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 400
    assert r.json()["code"] == "VALIDATION_ERROR"
