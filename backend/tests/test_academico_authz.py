"""Autorización de consultas académicas."""

from __future__ import annotations

import pytest

from apps.academico.authz import vinculo_estudiante
from apps.common.errors import StudentLinkNotFound
from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio


@pytest.mark.django_db
def test_vinculo_requerido():
    apo = Apoderado.objects.create(telefono="+51944444444")
    with pytest.raises(StudentLinkNotFound):
        vinculo_estudiante(apo, 999)


@pytest.mark.django_db
def test_vinculo_ok():
    apo = Apoderado.objects.create(telefono="+51944444445")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id="jean_piaget",
        id_estudiante=7,
        codigo_barras="70000007",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )
    v = vinculo_estudiante(apo, 7)
    assert v.id_estudiante == 7
