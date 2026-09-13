"""Pruebas de agenda mensual de asistencias."""

from __future__ import annotations

from datetime import date
from types import SimpleNamespace

import pytest

from apps.academico.services import agenda_mensual
from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio


def _apoderado(telefono: str, tenant_id: str, estudiante_id: int) -> Apoderado:
    apo = Apoderado.objects.create(telefono=telefono)
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id=tenant_id,
        id_estudiante=estudiante_id,
        codigo_barras=f"70{estudiante_id:06d}",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )
    apo.estudiante_activo_id = estudiante_id
    apo.estudiante_activo_tenant = tenant_id
    apo.save(update_fields=["estudiante_activo_id", "estudiante_activo_tenant"])
    return apo


def _parchear_agenda(monkeypatch, *, hoy: date, registros=None, alias="colegio_jean_piaget"):
    filas = registros if registros is not None else []

    class _QS:
        def using(self, _alias):
            return self

        def filter(self, **_kwargs):
            return filas

    monkeypatch.setattr("apps.academico.services.RegistroLlegada.objects", _QS())
    monkeypatch.setattr(
        "apps.academico.services.circuit_breaker.permite_intentar",
        lambda *_a, **_k: True,
    )
    monkeypatch.setattr(
        "apps.academico.services.circuit_breaker.registrar_exito",
        lambda *_a, **_k: None,
    )
    monkeypatch.setattr("apps.academico.services.tenant_alias", lambda _t: alias)
    monkeypatch.setattr("apps.academico.services._hoy_lima", lambda: hoy)


@pytest.mark.django_db
def test_agenda_mensual_sin_registros_marca_falta_o_sin_registro(monkeypatch):
    apo = _apoderado("+51977770001", "jean_piaget", 42)
    # Septiembre 2026: el hotfix JP (antes del 8) ya no aplica.
    _parchear_agenda(monkeypatch, hoy=date(2026, 9, 15))

    resultado = agenda_mensual(apo, estudiante_id=42, anio=2026, mes=9)
    assert len(resultado["items"]) == 30
    # 14-sep-2026 es lunes pasado → falta; 18-sep es viernes futuro → sin_registro
    dia_lunes = next(i for i in resultado["items"] if i["fecha"] == "2026-09-14")
    dia_futuro = next(i for i in resultado["items"] if i["fecha"] == "2026-09-18")
    dia_domingo = next(i for i in resultado["items"] if i["fecha"] == "2026-09-13")
    dia_arranque = next(i for i in resultado["items"] if i["fecha"] == "2026-09-07")
    dia_antes = next(i for i in resultado["items"] if i["fecha"] == "2026-09-04")
    assert dia_lunes["estado"] == "falta"
    assert dia_futuro["estado"] == "sin_registro"
    assert dia_domingo["estado"] == "sin_registro"
    assert dia_arranque["estado"] == "falta"
    assert dia_antes["estado"] == "sin_registro"


@pytest.mark.django_db
def test_agenda_jp_fin_de_semana_sin_falta(monkeypatch):
    apo = _apoderado("+51977770004", "jean_piaget", 44)
    _parchear_agenda(monkeypatch, hoy=date(2026, 9, 15))

    resultado = agenda_mensual(apo, estudiante_id=44, anio=2026, mes=9)
    sabado = next(i for i in resultado["items"] if i["fecha"] == "2026-09-12")
    domingo = next(i for i in resultado["items"] if i["fecha"] == "2026-09-13")
    assert sabado["estado"] == "sin_registro"
    assert domingo["estado"] == "sin_registro"


@pytest.mark.django_db
def test_agenda_academy_domingo_en_blanco_sabado_es_falta(monkeypatch):
    apo = _apoderado("+51977770005", "asis_academy", 45)
    _parchear_agenda(
        monkeypatch,
        hoy=date(2026, 3, 15),
        alias="colegio_asis_academy",
    )

    resultado = agenda_mensual(apo, estudiante_id=45, anio=2026, mes=3)
    sabado = next(i for i in resultado["items"] if i["fecha"] == "2026-03-07")
    domingo = next(i for i in resultado["items"] if i["fecha"] == "2026-03-08")
    assert sabado["estado"] == "falta"
    assert domingo["estado"] == "sin_registro"


@pytest.mark.django_db
def test_agenda_jp_conserva_registro_real_en_sabado(monkeypatch):
    apo = _apoderado("+51977770006", "jean_piaget", 46)
    reg = SimpleNamespace(
        fecha=date(2026, 9, 12),
        estado="A tiempo",
        hora_llegada=SimpleNamespace(strftime=lambda fmt: "08:10"),
        hora_salida=None,
        tipo_salida=None,
    )
    _parchear_agenda(monkeypatch, hoy=date(2026, 9, 15), registros=[reg])

    resultado = agenda_mensual(apo, estudiante_id=46, anio=2026, mes=9)
    sabado = next(i for i in resultado["items"] if i["fecha"] == "2026-09-12")
    assert sabado["estado"] == "a_tiempo"
    assert sabado["hora_entrada"] == "08:10"


@pytest.mark.django_db
def test_agenda_mensual_con_registro(monkeypatch):
    apo = _apoderado("+51977770002", "jean_piaget", 43)
    reg = SimpleNamespace(
        fecha=date(2026, 3, 10),
        estado="Presente",
        hora_llegada=SimpleNamespace(strftime=lambda fmt: "07:55"),
        hora_salida=None,
        tipo_salida=None,
    )
    _parchear_agenda(monkeypatch, hoy=date(2026, 3, 15), registros=[reg])
    monkeypatch.setattr(
        "apps.academico.services._mapear_estado",
        lambda e: "presente",
    )

    resultado = agenda_mensual(apo, estudiante_id=43, anio=2026, mes=3)
    dia = next(i for i in resultado["items"] if i["fecha"] == "2026-03-10")
    assert dia["estado"] == "presente"
    assert dia["hora_entrada"] == "07:55"
