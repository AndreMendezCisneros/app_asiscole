"""Pruebas de administración."""

from __future__ import annotations

import pytest

from apps.administracion.services import listar_flags, suspender_cuenta
from apps.cuentas.models import CUENTA_SUSPENDIDA, Apoderado


@pytest.mark.django_db
def test_feature_flags_incluye_notas_y_citacion():
    flags = listar_flags()
    assert "notas" in flags
    assert flags["notas"] is False
    assert "citacion" in flags
    assert flags["citacion"] is False


@pytest.mark.django_db
def test_suspender_cuenta():
    apo = Apoderado.objects.create(telefono="+51955555555")
    suspender_cuenta(apo.pk, motivo="Deuda de pensión", actor="admin:1", notificar_push=False)
    apo.refresh_from_db()
    assert apo.estado == CUENTA_SUSPENDIDA
