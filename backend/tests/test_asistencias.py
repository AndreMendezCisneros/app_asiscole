"""Pruebas de agenda mensual de asistencias."""

from __future__ import annotations

from datetime import date
from types import SimpleNamespace

import pytest

from apps.academico.services import agenda_mensual
from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio


@pytest.mark.django_db
def test_agenda_mensual_sin_registros_marca_falta_o_sin_registro(monkeypatch):
    apo = Apoderado.objects.create(telefono="+51977770001")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=42,
        codigo_barras="70000042",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )
    apo.estudiante_activo_id = 42
    apo.estudiante_activo_tenant = "jean_piaget"
    apo.save(update_fields=["estudiante_activo_id", "estudiante_activo_tenant"])

    class _QS:
        def using(self, _alias):
            return self

        def filter(self, **_kwargs):
            return []

    monkeypatch.setattr(
        "apps.academico.services.RegistroLlegada.objects",
        _QS(),
    )
    monkeypatch.setattr(
        "apps.academico.services.circuit_breaker.permite_intentar",
        lambda *_a, **_k: True,
    )
    monkeypatch.setattr(
        "apps.academico.services.circuit_breaker.registrar_exito",
        lambda *_a, **_k: None,
    )
    monkeypatch.setattr(
        "apps.academico.services.tenant_alias",
        lambda _t: "colegio_jean_piaget",
    )
    monkeypatch.setattr(
        "apps.academico.services._hoy_lima",
        lambda: date(2026, 3, 15),
    )

    resultado = agenda_mensual(apo, estudiante_id=42, anio=2026, mes=3)
    assert len(resultado["items"]) == 31
    # Día pasado → falta; día futuro → sin_registro
    dia_1 = next(i for i in resultado["items"] if i["fecha"] == "2026-03-01")
    dia_20 = next(i for i in resultado["items"] if i["fecha"] == "2026-03-20")
    assert dia_1["estado"] == "falta"
    assert dia_20["estado"] == "sin_registro"


@pytest.mark.django_db
def test_agenda_mensual_con_registro(monkeypatch):
    apo = Apoderado.objects.create(telefono="+51977770002")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=43,
        codigo_barras="70000043",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )

    reg = SimpleNamespace(
        fecha=date(2026, 3, 10),
        estado="Presente",
        hora_llegada=SimpleNamespace(strftime=lambda fmt: "07:55"),
        hora_salida=None,
        tipo_salida=None,
    )

    class _QS:
        def using(self, _alias):
            return self

        def filter(self, **_kwargs):
            return [reg]

    monkeypatch.setattr("apps.academico.services.RegistroLlegada.objects", _QS())
    monkeypatch.setattr(
        "apps.academico.services.circuit_breaker.permite_intentar",
        lambda *_a, **_k: True,
    )
    monkeypatch.setattr(
        "apps.academico.services.circuit_breaker.registrar_exito",
        lambda *_a, **_k: None,
    )
    monkeypatch.setattr(
        "apps.academico.services.tenant_alias",
        lambda _t: "colegio_jean_piaget",
    )
    monkeypatch.setattr(
        "apps.academico.services._hoy_lima",
        lambda: date(2026, 3, 15),
    )
    monkeypatch.setattr(
        "apps.academico.services._mapear_estado",
        lambda e: "presente",
    )

    resultado = agenda_mensual(apo, estudiante_id=43, anio=2026, mes=3)
    dia = next(i for i in resultado["items"] if i["fecha"] == "2026-03-10")
    assert dia["estado"] == "presente"
    assert dia["hora_entrada"] == "07:55"
