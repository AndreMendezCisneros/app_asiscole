"""Purga de tokens de push que quedaron vivos sin sesion abierta."""

from __future__ import annotations

from datetime import timedelta

import pytest
from django.utils import timezone

from apps.cuentas.models import (
    SESION_ACTIVA,
    SESION_REVOCADA,
    Apoderado,
    PushToken,
    SesionActiva,
)
from apps.cuentas.services import desactivar_push_sin_sesion


def _apoderado(telefono: str) -> Apoderado:
    return Apoderado.objects.create(telefono=telefono)


def _token(apoderado: Apoderado, device_id: str = "dev-1") -> PushToken:
    return PushToken.objects.create(
        apoderado=apoderado,
        device_id=device_id,
        token=f"tok-{apoderado.pk}-{device_id}",
        plataforma="android",
        activo=True,
    )


def _sesion(
    apoderado: Apoderado,
    *,
    estado: str = SESION_ACTIVA,
    device_id: str = "dev-1",
    dias: int = 10,
) -> SesionActiva:
    return SesionActiva.objects.create(
        apoderado=apoderado,
        device_id=device_id,
        estado=estado,
        expira_en=timezone.now() + timedelta(days=dias),
    )


@pytest.mark.django_db
def test_desactiva_el_token_de_una_cuenta_sin_sesion():
    """El caso del logout que no llego al servidor."""
    apo = _apoderado("+51955551001")
    token = _token(apo)
    _sesion(apo, estado=SESION_REVOCADA)

    assert desactivar_push_sin_sesion() == 1
    token.refresh_from_db()
    assert token.activo is False


@pytest.mark.django_db
def test_conserva_el_token_de_una_cuenta_con_sesion_activa():
    apo = _apoderado("+51955551002")
    token = _token(apo)
    _sesion(apo)

    assert desactivar_push_sin_sesion() == 0
    token.refresh_from_db()
    assert token.activo is True


@pytest.mark.django_db
def test_conserva_el_token_si_la_sesion_activa_ya_vencio():
    """Al volver a entrar se renueva la sesion y se re-registra el token."""
    apo = _apoderado("+51955551003")
    token = _token(apo)
    _sesion(apo, dias=-1)

    assert desactivar_push_sin_sesion() == 0
    token.refresh_from_db()
    assert token.activo is True


@pytest.mark.django_db
def test_es_idempotente():
    apo = _apoderado("+51955551004")
    _token(apo)

    assert desactivar_push_sin_sesion() == 1
    assert desactivar_push_sin_sesion() == 0


@pytest.mark.django_db
def test_dry_run_no_toca_nada():
    apo = _apoderado("+51955551005")
    token = _token(apo)

    assert desactivar_push_sin_sesion(simular=True) == 1
    token.refresh_from_db()
    assert token.activo is True


@pytest.mark.django_db
def test_no_mezcla_cuentas():
    """Una cuenta sin sesion no arrastra los tokens de las demas."""
    sin_sesion = _apoderado("+51955551006")
    token_huerfano = _token(sin_sesion)

    con_sesion = _apoderado("+51955551007")
    token_vivo = _token(con_sesion, device_id="dev-2")
    _sesion(con_sesion, device_id="dev-2")

    assert desactivar_push_sin_sesion() == 1
    token_huerfano.refresh_from_db()
    token_vivo.refresh_from_db()
    assert token_huerfano.activo is False
    assert token_vivo.activo is True
