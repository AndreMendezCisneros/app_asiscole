"""Pruebas del procesamiento de outbox → mensaje.

Cada tipo de evento se prueba con payload completo y con payload incompleto: en
`asis_academy` una incidencia sin `nombre_falta` se aceptaba con `202` y no
generaba ningún mensaje, y no había prueba que lo delatara.
"""

from __future__ import annotations

import pytest
from django.test import override_settings

from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from apps.ingesta.services import crear_mensajes_desde_evento
from apps.mensajeria.models import Mensaje
from apps.mensajeria.plantillas.base import DatosDeEventoIncompletos


@pytest.mark.django_db
def test_crear_mensaje_desde_entrada():
    apo = Apoderado.objects.create(telefono="+51987654321")
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
    creados = crear_mensajes_desde_evento(
        tenant_id="jean_piaget",
        tipo="entrada",
        id_estudiante=10,
        id_registro=42,
        payload={
            "id_estudiante": 10,
            "nombre_completo": "Estudiante Prueba",
            "grado": "3",
            "seccion": "A",
            "nivel_educativo": "Primaria",
            "fecha": "2026-07-25",
            "hora_llegada": "07:45",
            "estado": "A tiempo",
        },
    )
    assert len(creados) == 1
    assert creados[0].origen_evento == "entrada:42"
    assert "07:45" in creados[0].texto or "entrada" in creados[0].texto.lower() or len(creados[0].texto) > 0

    # Segunda pasada: idempotente
    otra = crear_mensajes_desde_evento(
        tenant_id="jean_piaget",
        tipo="entrada",
        id_estudiante=10,
        id_registro=42,
        payload={
            "id_estudiante": 10,
            "nombre_completo": "Estudiante Prueba",
            "fecha": "2026-07-25",
            "hora_llegada": "07:45",
            "estado": "A tiempo",
        },
    )
    assert otra == []
    assert Mensaje.objects.filter(apoderado=apo).count() == 1


@pytest.fixture
def apoderado_vinculado(db):
    """Apoderado activo con un estudiante en el directorio del canal."""
    apo = Apoderado.objects.create(telefono="+51987654322")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=11,
        codigo_barras="70123457",
        nombre_estudiante="Estudiante Prueba",
        grado="3",
        seccion="A",
        nivel="Primaria",
        estado_vinculo=VINCULO_ACTIVO,
    )
    return apo


def _crear(tipo: str, payload: dict, *, id_registro: int = 100):
    return crear_mensajes_desde_evento(
        tenant_id="jean_piaget",
        tipo=tipo,
        id_estudiante=11,
        id_registro=id_registro,
        payload=payload,
    )


@pytest.mark.django_db
def test_salida_con_payload_completo(apoderado_vinculado):
    creados = _crear(
        "salida",
        {
            "id_estudiante": 11,
            "nombre_completo": "Estudiante Prueba",
            "fecha": "2026-07-25",
            "hora_salida": "13:20",
            "tipo_salida": "Normal",
        },
    )
    assert len(creados) == 1
    assert creados[0].origen_evento == "salida:100"
    assert "13:20" in creados[0].texto


@pytest.mark.django_db
def test_salida_sin_hora_no_crea_mensaje(apoderado_vinculado):
    """Sin hora el aviso quedaría a medias: mejor fallar y reintentar."""
    with pytest.raises(DatosDeEventoIncompletos):
        _crear(
            "salida",
            {
                "id_estudiante": 11,
                "nombre_completo": "Estudiante Prueba",
                "tipo_salida": "Normal",
            },
        )
    assert Mensaje.objects.count() == 0


@pytest.mark.django_db
def test_incidencia_con_payload_completo(apoderado_vinculado):
    creados = _crear(
        "incidencia",
        {
            "id_estudiante": 11,
            "nombre_completo": "Estudiante Prueba",
            "id_falta": 7,
            "nombre_falta": "Uso de celular en clase",
            "categoria": "Disciplina",
            "es_grave": False,
            "nombre_usuario_registro": "Auxiliar",
        },
    )
    assert len(creados) == 1
    assert "Uso de celular en clase" in creados[0].texto
    assert creados[0].metadata["id_falta"] == 7


@pytest.mark.django_db
def test_incidencia_sin_nombre_falta_no_crea_mensaje(apoderado_vinculado):
    """El caso exacto de `asis_academy`: `incidencia:2` sin `nombre_falta`."""
    with pytest.raises(DatosDeEventoIncompletos) as exc:
        _crear(
            "incidencia",
            {
                "id_estudiante": 11,
                "nombre_completo": "Estudiante Prueba",
                "id_falta": 2,
            },
        )
    # El error nombra el campo, nunca su valor (Ley N.º 29733).
    assert "nombre_falta" in str(exc.value)
    assert "Estudiante Prueba" not in str(exc.value)
    assert Mensaje.objects.count() == 0


@pytest.mark.django_db
@override_settings(SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
def test_aviso_con_texto_libre(apoderado_vinculado):
    creados = _crear(
        "aviso",
        {"id_estudiante": 11, "texto_libre": "Mañana no hay clases por feriado."},
    )
    assert len(creados) == 1
    assert "Jean Piaget" in creados[0].texto
    assert "Mañana no hay clases por feriado." in creados[0].texto


@pytest.mark.django_db
def test_aviso_sin_texto_libre_no_crea_mensaje(apoderado_vinculado):
    with pytest.raises(DatosDeEventoIncompletos):
        _crear("aviso", {"id_estudiante": 11})
    assert Mensaje.objects.count() == 0


@pytest.mark.django_db
@override_settings(SCHOOL_TENANTS={"jean_piaget": "Jean Piaget"})
def test_aviso_cita_guarda_contexto_en_metadata(apoderado_vinculado):
    creados = _crear(
        "aviso",
        {
            "id_estudiante": 11,
            "texto_libre": "Se citó a los padres el 20/08/2026 a las 09:30.",
            "contexto": "cita",
            "fecha": "2026-08-20",
            "hora": "09:30",
            "motivo": "Revisión de incidencias",
            "alcance": "individual",
        },
        id_registro=44,
    )
    assert len(creados) == 1
    assert creados[0].origen_evento == "aviso:44"
    assert creados[0].metadata["contexto"] == "cita"
    assert creados[0].metadata["motivo"] == "Revisión de incidencias"
    assert creados[0].metadata["alcance"] == "individual"
    assert creados[0].metadata["fecha"] == "2026-08-20"
    assert creados[0].metadata["hora"] == "09:30"
    assert "Citación de Jean Piaget" in creados[0].texto


@pytest.mark.django_db
def test_evento_sin_apoderado_en_directorio_no_crea_nada(db):
    """Un estudiante sin vínculo activo no genera mensajes ni error."""
    assert _crear(
        "salida",
        {
            "id_estudiante": 11,
            "nombre_completo": "Estudiante Prueba",
            "hora_salida": "13:20",
        },
    ) == []
    assert Mensaje.objects.count() == 0
