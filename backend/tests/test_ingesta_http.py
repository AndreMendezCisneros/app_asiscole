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
@pytest.mark.parametrize(
    ("tipo", "payload"),
    [
        (
            "salida",
            {
                "nombre_completo": "Estudiante Prueba",
                "fecha": "2026-07-25",
                "hora_salida": "13:20",
                "tipo_salida": "Autorizada",
            },
        ),
        (
            "incidencia",
            {
                "nombre_completo": "Estudiante Prueba",
                "id_falta": 7,
                "nombre_falta": "Uso de celular en clase",
                "categoria": "Disciplina",
            },
        ),
        ("aviso", {"texto_libre": "Mañana no hay clases."}),
    ],
)
def test_ingesta_http_crea_mensaje_por_tipo(api, apoderado_con_vinculo, tipo, payload):
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(tipo=tipo, payload=payload, id_registro=9100),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 202
    assert r.json()["creados"] == 1
    assert Mensaje.objects.filter(apoderado=apoderado_con_vinculo, tipo=tipo).count() == 1


@pytest.mark.django_db
@override_settings(INGEST_API_KEY=CLAVE, SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
@pytest.mark.parametrize(
    ("tipo", "payload"),
    [
        # Sin hora la salida no se puede redactar.
        ("salida", {"nombre_completo": "Estudiante Prueba", "tipo_salida": "Normal"}),
        # El caso de `asis_academy`: incidencia sin `nombre_falta`.
        ("incidencia", {"nombre_completo": "Estudiante Prueba", "id_falta": 2}),
        ("aviso", {"nombre_completo": "Estudiante Prueba"}),
    ],
)
def test_ingesta_http_payload_incompleto_400(api, apoderado_con_vinculo, tipo, payload):
    """El emisor debe enterarse: antes recibía 202 y nadie notaba el hueco."""
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(tipo=tipo, payload=payload, id_registro=9200),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 400
    assert r.json()["code"] == "VALIDATION_ERROR"
    assert Mensaje.objects.count() == 0


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


@pytest.mark.django_db
@override_settings(
    INGEST_API_KEY=CLAVE,
    SCHOOL_TENANTS={"jean_piaget": "Jean Piaget", "asis_academy": "Academy"},
)
def test_ingesta_http_aviso_cita_en_bandeja(api, apoderado_con_vinculo):
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(
            tipo="aviso",
            id_registro=44,
            payload={
                "texto_libre": "Se citó a los padres el 20/08/2026 a las 09:30.",
                "contexto": "cita",
                "fecha": "2026-08-20",
                "hora": "09:30",
                "motivo": "Revisión de incidencias",
                "alcance": "individual",
            },
        ),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 202
    assert r.json()["creados"] == 1
    assert r.json()["origen_evento"] == "aviso:44"
    mensaje = Mensaje.objects.get(apoderado=apoderado_con_vinculo)
    assert mensaje.tipo == "aviso"
    assert mensaje.metadata["contexto"] == "cita"


@pytest.mark.django_db
@override_settings(
    INGEST_API_KEY=CLAVE,
    SCHOOL_TENANTS={"jean_piaget": "Jean Piaget", "asis_academy": "Academy"},
)
def test_ingesta_http_nota_no_crea_mensaje(api, apoderado_con_vinculo):
    from apps.mensajeria.models import NotaSemanal

    payload = {
        "semana_codigo": "2026-02",
        "semana_etiqueta": "Semana 2",
        "fecha_inicio": "2026-02-03",
        "fecha_fin": "2026-02-09",
        "nota": "18.5",
        "nota_maxima": "20",
        "area_nombre": "Ciencias de la Salud",
        "carrera": "Medicina Humana",
        "texto_libre": "Se registró la nota semanal.",
    }
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(tipo="nota", id_registro=991, payload=payload),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 202
    assert r.json()["creados"] == 1
    assert r.json()["origen_evento"] == "nota:991"
    assert Mensaje.objects.count() == 0
    fila = NotaSemanal.objects.get()
    assert fila.id_estudiante == 10
    assert fila.nota == "18.5"
    assert fila.semana_etiqueta == "Semana 2"
    assert fila.tenant_id == "jean_piaget"

    otra = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(tipo="nota", id_registro=991, payload=payload),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert otra.status_code == 202
    assert otra.json()["creados"] == 0
    assert NotaSemanal.objects.count() == 1


@pytest.mark.django_db
@override_settings(
    INGEST_API_KEY=CLAVE,
    SCHOOL_TENANTS={"jean_piaget": "Jean Piaget", "asis_academy": "Academy"},
)
def test_ingesta_http_aviso_contexto_nota_va_a_seccion(api, apoderado_con_vinculo):
    """Academy aún manda tipo=aviso + contexto=nota; no debe llenar la bandeja."""
    from apps.mensajeria.models import NotaSemanal

    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(
            tipo="aviso",
            id_registro=65,
            payload={
                "texto_libre": "Se registró la nota semanal: 18.5/20 (Semana 2).",
                "semana": "2026-02",
                "nota": "18.5",
                "contexto": "nota",
                "carrera": "Medicina Humana",
                "area": "Ciencias de la Salud",
            },
        ),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 202
    assert r.json()["creados"] == 1
    assert r.json()["origen_evento"] == "nota:65"
    assert Mensaje.objects.count() == 0
    fila = NotaSemanal.objects.get()
    assert fila.id_estudiante == 10
    assert fila.nota == "18.5"
    assert fila.semana_codigo == "2026-02"
    assert fila.semana_etiqueta == "Semana 2"
    assert fila.area_nombre == "Ciencias de la Salud"
    assert fila.carrera == "Medicina Humana"


@pytest.mark.django_db
@override_settings(INGEST_API_KEY=CLAVE, SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
def test_ingesta_http_aviso_cita_no_es_nota(api, apoderado_con_vinculo):
    from apps.mensajeria.models import NotaSemanal

    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(
            tipo="aviso",
            id_registro=44,
            payload={
                "texto_libre": "Se citó a los padres el 20/08/2026 a las 09:30.",
                "contexto": "cita",
                "fecha": "2026-08-20",
                "hora": "09:30",
                "motivo": "Revisión de incidencias",
                "alcance": "individual",
            },
        ),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 202
    assert Mensaje.objects.count() == 1
    assert NotaSemanal.objects.count() == 0


@pytest.mark.django_db
@override_settings(INGEST_API_KEY=CLAVE, SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
def test_ingesta_http_nota_incompleta_400(api, apoderado_con_vinculo):
    r = api.post(
        "/v0.1/ingesta/eventos",
        _cuerpo(tipo="nota", id_registro=992, payload={"semana_codigo": "2026-02"}),
        format="json",
        HTTP_X_ASISCOLE_INGEST_KEY=CLAVE,
    )
    assert r.status_code == 400
    assert r.json()["code"] == "VALIDATION_ERROR"
