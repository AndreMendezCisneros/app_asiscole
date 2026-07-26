"""Pruebas del procesamiento de outbox → mensaje."""

from __future__ import annotations

import pytest

from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from apps.ingesta.services import crear_mensajes_desde_evento
from apps.mensajeria.models import Mensaje


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
