"""Pruebas de perfil y eliminación de cuenta."""

from __future__ import annotations

import pytest

from apps.common.errors import StudentLinkNotFound
from apps.cuentas.models import CUENTA_ELIMINADA, SESION_ACTIVA, Apoderado, SesionActiva
from apps.cuentas.perfil_services import eliminar_cuenta, listar_estudiantes, obtener_perfil
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from django.utils import timezone
from datetime import timedelta
import uuid


@pytest.mark.django_db
def test_listar_estudiantes_marca_activo():
    apo = Apoderado.objects.create(
        telefono="+51977777777",
        estudiante_activo_id=1,
        estudiante_activo_tenant="jean_piaget",
    )
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=1,
        codigo_barras="70111111",
        nombre_estudiante="Ana",
        estado_vinculo=VINCULO_ACTIVO,
    )
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=2,
        codigo_barras="70222222",
        nombre_estudiante="Luis",
        estado_vinculo=VINCULO_ACTIVO,
    )
    items = listar_estudiantes(apo)["items"]
    assert len(items) == 2
    activos = [i for i in items if i["activo"]]
    assert len(activos) == 1
    assert activos[0]["id"] == 1


@pytest.mark.django_db
def test_eliminar_cuenta_anonimiza_y_revoca():
    apo = Apoderado.objects.create(telefono="+51988888888")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=3,
        codigo_barras="70333333",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )
    SesionActiva.objects.create(
        apoderado=apo,
        device_id="dev-1",
        jti=uuid.uuid4(),
        estado=SESION_ACTIVA,
        expira_en=timezone.now() + timedelta(days=5),
    )
    eliminar_cuenta(apo, "70333333")
    apo.refresh_from_db()
    assert apo.estado == CUENTA_ELIMINADA
    assert apo.telefono.startswith("deleted:")
    assert SesionActiva.objects.filter(apoderado=apo, estado=SESION_ACTIVA).count() == 0


@pytest.mark.django_db
def test_eliminar_cuenta_exige_documento_vinculado():
    apo = Apoderado.objects.create(telefono="+51999999999")
    with pytest.raises(StudentLinkNotFound):
        eliminar_cuenta(apo, "00000000")


@pytest.mark.django_db
def test_perfil_enmascara_telefono():
    apo = Apoderado.objects.create(telefono="+51912345678")
    perfil = obtener_perfil(apo)
    assert "*" in perfil["telefono"]
    assert "912345678" not in perfil["telefono"]
