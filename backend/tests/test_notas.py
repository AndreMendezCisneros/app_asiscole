"""Listado de notas semanales: aislamiento por vínculo y por tenant."""

from __future__ import annotations

from datetime import date

import pytest

from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from apps.mensajeria.models import NotaSemanal
from tests.conftest import con_bearer, cuerpo_login

pytestmark = pytest.mark.django_db


def _nota(*, tenant_id: str, id_estudiante: int, id_registro: int, valor: str) -> NotaSemanal:
    return NotaSemanal.objects.create(
        tenant_id=tenant_id,
        id_estudiante=id_estudiante,
        id_registro=id_registro,
        nota=valor,
        nota_maxima="20",
        semana_codigo="2026-02",
        semana_etiqueta="Semana 2",
        fecha_inicio=date(2026, 2, 3),
        fecha_fin=date(2026, 2, 9),
        area_nombre="Ciencias de la Salud",
    )


def test_get_notas_solo_del_tenant_del_vinculo(api, vinculo_en_directorio, colegios):
    """El id_estudiante 101 en Academy no se filtra al padre de Jean Piaget."""
    _nota(tenant_id="jean_piaget", id_estudiante=101, id_registro=1, valor="18.5")
    _nota(tenant_id="asis_academy", id_estudiante=101, id_registro=1, valor="05")

    sesion = api.post("/v0.1/auth/login", cuerpo_login(), format="json")
    assert sesion.status_code == 200
    token = sesion.json()["data_token"]

    r = api.get("/v0.1/notas", {"estudiante_id": 101}, **con_bearer(token))
    assert r.status_code == 200
    items = r.json()["items"]
    assert len(items) == 1
    assert items[0]["nota"] == "18.5"
    assert items[0]["semana_etiqueta"] == "Semana 2"


def test_get_notas_estudiante_ajeno_404(api, vinculo_en_directorio, colegios):
    sesion = api.post("/v0.1/auth/login", cuerpo_login(), format="json")
    token = sesion.json()["data_token"]
    r = api.get("/v0.1/notas", {"estudiante_id": 999}, **con_bearer(token))
    assert r.status_code == 404
    assert r.json()["code"] == "STUDENT_LINK_NOT_FOUND"


def test_listar_notas_prefiere_tenant_activo():
    from apps.academico.services import listar_notas

    apo = Apoderado.objects.create(
        telefono="+51955550001",
        estudiante_activo_id=10,
        estudiante_activo_tenant="asis_academy",
    )
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=10,
        codigo_barras="70000010",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="asis_academy",
        id_estudiante=10,
        codigo_barras="70000011",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )
    _nota(tenant_id="jean_piaget", id_estudiante=10, id_registro=7, valor="11")
    _nota(tenant_id="asis_academy", id_estudiante=10, id_registro=7, valor="18.5")

    items = listar_notas(apo, estudiante_id=10)["items"]
    assert [i["nota"] for i in items] == ["18.5"]


def test_serializar_nota_etiqueta_y_fecha_de_emision():
    from apps.mensajeria.notas import serializar_nota

    fila = _nota(tenant_id="jean_piaget", id_estudiante=10, id_registro=3, valor="15")
    fila.semana_codigo = "2026-02"
    fila.semana_etiqueta = "2026-02"
    fila.fecha_inicio = date(2026, 2, 3)
    fila.fecha_fin = date(2026, 2, 9)
    fila.carrera = "Medicina Humana"
    fila.save()
    data = serializar_nota(fila)
    assert data["semana_etiqueta"] == "Semana 2"
    assert data["fecha_inicio"] == "2026-02-03"
    assert data["fecha_fin"] == "2026-02-09"
    assert data["carrera"] == "Medicina Humana"
    assert data["registrado_en"]


def test_migrar_avisos_contexto_nota_desde_bandeja():
    from apps.mensajeria.models import Mensaje
    from apps.mensajeria.notas import migrar_avisos_contexto_nota

    apo = Apoderado.objects.create(telefono="+51955550002")
    Mensaje.objects.create(
        apoderado=apo,
        tenant_id="asis_academy",
        id_estudiante=65,
        tipo="aviso",
        texto=(
            "Se registró la nota semanal: 16/20 (2026-02). "
            "Carrera: Medicina Humana. Área: Ciencias de la Salud."
        ),
        origen_evento="aviso:65",
        metadata={"contexto": "nota", "id_estudiante": 65, "id_registro": 65},
    )
    Mensaje.objects.create(
        apoderado=apo,
        tenant_id="asis_academy",
        id_estudiante=65,
        tipo="aviso",
        texto="Se citó a los padres.",
        origen_evento="aviso:44",
        metadata={"contexto": "cita"},
    )
    assert migrar_avisos_contexto_nota() == 1
    assert migrar_avisos_contexto_nota() == 0
    fila = NotaSemanal.objects.get()
    assert fila.id_estudiante == 65
    assert fila.id_registro == 65
    assert fila.nota == "16"
    assert fila.nota_maxima == "20"
    assert fila.semana_etiqueta == "Semana 2"
    assert fila.carrera == "Medicina Humana"
    assert fila.area_nombre == "Ciencias de la Salud"
