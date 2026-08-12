"""Pruebas de administración (aislamiento por tenant)."""

from __future__ import annotations

import pytest

from apps.administracion.services import (
    listar_apoderados,
    listar_flags,
    suspender_cuenta,
)
from apps.common.errors import ValidationError
from apps.cuentas.models import CUENTA_SUSPENDIDA, Apoderado, identidad_administrador
from apps.directorio.models import VINCULO_ACTIVO, Directorio

TENANT_A = "jean_piaget"
TENANT_B = "otro_colegio"


@pytest.mark.django_db
def test_feature_flags_incluye_notas_y_citacion():
    flags = listar_flags()
    assert "notas" in flags
    assert flags["notas"] is False
    assert "citacion" in flags
    assert flags["citacion"] is False


@pytest.mark.django_db
def test_suspender_cuenta_del_mismo_tenant():
    apo = Apoderado.objects.create(telefono="+51955555555")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id=TENANT_A,
        id_estudiante=1,
        codigo_barras="55500001",
        nombre_estudiante="Estudiante A",
        estado_vinculo=VINCULO_ACTIVO,
    )
    suspender_cuenta(
        apo.pk,
        motivo="Deuda de pensión",
        actor="admin:1",
        tenant_id=TENANT_A,
        notificar_push=False,
    )
    apo.refresh_from_db()
    assert apo.estado == CUENTA_SUSPENDIDA


@pytest.mark.django_db
def test_admin_no_suspende_apoderado_de_otro_tenant():
    apo = Apoderado.objects.create(telefono="+51955555556")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id=TENANT_B,
        id_estudiante=2,
        codigo_barras="55500002",
        nombre_estudiante="Estudiante B",
        estado_vinculo=VINCULO_ACTIVO,
    )
    with pytest.raises(ValidationError):
        suspender_cuenta(
            apo.pk,
            motivo="Deuda de pensión",
            actor="admin:1",
            tenant_id=TENANT_A,
            notificar_push=False,
        )
    apo.refresh_from_db()
    assert apo.estado != CUENTA_SUSPENDIDA


@pytest.mark.django_db
def test_listar_apoderados_solo_del_tenant():
    apo_a = Apoderado.objects.create(telefono="+51955550001")
    apo_b = Apoderado.objects.create(telefono="+51955550002")
    Directorio.objects.create(
        telefono=apo_a.telefono,
        tenant_id=TENANT_A,
        id_estudiante=10,
        codigo_barras="55500010",
        nombre_estudiante="A",
        estado_vinculo=VINCULO_ACTIVO,
    )
    Directorio.objects.create(
        telefono=apo_b.telefono,
        tenant_id=TENANT_B,
        id_estudiante=11,
        codigo_barras="55500011",
        nombre_estudiante="B",
        estado_vinculo=VINCULO_ACTIVO,
    )
    # Identidad admin solo para documentar el patrón; el filtro usa tenant_id.
    Apoderado.objects.create(telefono=identidad_administrador(TENANT_A, 99))

    resultado = listar_apoderados(tenant_id=TENANT_A)
    ids = {item["id"] for item in resultado["items"]}
    assert apo_a.pk in ids
    assert apo_b.pk not in ids
