"""Pruebas del traspaso de dispositivo (RF-A09 / CU-09, ADR-06).

Es el camino que evita que cambiar de telefono obligue a llamar al colegio: el
equipo nuevo pide, el equipo con la sesion viva aprueba y el nuevo entra.
"""

from __future__ import annotations

from datetime import timedelta

import pytest
from django.utils import timezone

from apps.cuentas.models import (
    SESION_ACTIVA,
    SESION_TRANSFERIDA,
    TRANSFERENCIA_APROBADA,
    TRANSFERENCIA_EXPIRADA,
    TRANSFERENCIA_PENDIENTE,
    TRANSFERENCIA_RECHAZADA,
    SesionActiva,
    TransferenciaSesion,
)
from tests.conftest import DEVICE_A, DEVICE_B, TELEFONO, con_bearer, cuerpo_login

URL_LOGIN = "/v0.1/auth/login"
URL_SOLICITAR = "/v0.1/auth/session-transfer/request"

pytestmark = pytest.mark.django_db


def _url_transferencia(id_transferencia, sufijo: str = "", *, token: str | None = None) -> str:
    base = f"/v0.1/auth/session-transfer/{id_transferencia}{sufijo}"
    if token and not sufijo:
        return f"{base}?token={token}"
    return base


def _cuerpo_solicitud(device_id: str = DEVICE_B) -> dict:
    return {
        "telefono": TELEFONO,
        "documento_estudiante": cuerpo_login()["documento_estudiante"],
        "device_id": device_id,
    }


def test_flujo_completo_solicitar_aprobar_y_entrar(api, vinculo_en_directorio):
    """El camino feliz de punta a punta."""
    # El equipo A tiene la sesion.
    primero = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    assert primero.status_code == 200
    token_a = primero.json()["session_token"]

    # El equipo B choca con el 409.
    assert api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_B), format="json").status_code == 409

    # B pide el traspaso.
    solicitud = api.post(URL_SOLICITAR, _cuerpo_solicitud(), format="json")
    assert solicitud.status_code == 202
    cuerpo = solicitud.json()
    assert set(cuerpo) == {"id", "estado", "expira_en", "token_consulta"}
    assert cuerpo["estado"] == TRANSFERENCIA_PENDIENTE
    assert cuerpo["token_consulta"]

    # Sin token → 410 (anti-IDOR).
    assert api.get(_url_transferencia(cuerpo["id"])).status_code == 410

    # B consulta el estado mientras espera.
    consulta = api.get(_url_transferencia(cuerpo["id"], token=cuerpo["token_consulta"]))
    assert consulta.status_code == 200
    assert consulta.json()["estado"] == TRANSFERENCIA_PENDIENTE

    # A aprueba desde su sesion.
    aprobacion = api.post(_url_transferencia(cuerpo["id"], "/approve"), **con_bearer(token_a))
    assert aprobacion.status_code == 204

    transferencia = TransferenciaSesion.objects.get()
    assert transferencia.estado == TRANSFERENCIA_APROBADA
    assert SesionActiva.objects.get().estado == SESION_TRANSFERIDA

    # Ahora B entra sin 409 y A se queda sin sesion.
    entrada_b = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_B), format="json")
    assert entrada_b.status_code == 200
    assert SesionActiva.objects.filter(estado=SESION_ACTIVA).count() == 1
    assert SesionActiva.objects.get(estado=SESION_ACTIVA).device_id == DEVICE_B

    # El token del equipo viejo ya no refresca.
    assert api.post("/v0.1/auth/refresh-data", **con_bearer(token_a)).status_code in (401, 410)


def test_transferencia_expirada_devuelve_410(api, vinculo_en_directorio):
    """Pasado el TTL la solicitud se marca `expired` y deja de servir."""
    primero = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    token_a = primero.json()["session_token"]

    solicitud = api.post(URL_SOLICITAR, _cuerpo_solicitud(), format="json")
    cuerpo = solicitud.json()
    id_transferencia = cuerpo["id"]
    token = cuerpo["token_consulta"]

    # Se envejece la solicitud mas alla de su TTL.
    TransferenciaSesion.objects.update(expira_en=timezone.now() - timedelta(seconds=1))

    consulta = api.get(_url_transferencia(id_transferencia, token=token))
    assert consulta.status_code == 410
    assert consulta.json()["code"] == "TRANSFER_EXPIRED"
    assert TransferenciaSesion.objects.get().estado == TRANSFERENCIA_EXPIRADA

    aprobacion = api.post(_url_transferencia(id_transferencia, "/approve"), **con_bearer(token_a))
    assert aprobacion.status_code == 410
    assert SesionActiva.objects.get().estado == SESION_ACTIVA


def test_una_segunda_solicitud_pendiente_devuelve_409(api, vinculo_en_directorio):
    """Un solo pedido a la vez: el equipo activo no puede ser bombardeado."""
    api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    assert api.post(URL_SOLICITAR, _cuerpo_solicitud(), format="json").status_code == 202

    repetida = api.post(URL_SOLICITAR, _cuerpo_solicitud("device-c"), format="json")

    assert repetida.status_code == 409
    assert repetida.json()["code"] == "TRANSFER_ALREADY_PENDING"


def test_el_limite_por_hora_devuelve_429(api, vinculo_en_directorio, settings):
    """RF-A09: como maximo `TRANSFER_MAX_PER_HOUR` solicitudes por cuenta."""
    settings.TRANSFER_MAX_PER_HOUR = 1
    token_a = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json").json()[
        "session_token"
    ]

    primera = api.post(URL_SOLICITAR, _cuerpo_solicitud(), format="json")
    assert primera.status_code == 202
    api.post(_url_transferencia(primera.json()["id"], "/reject"), **con_bearer(token_a))

    segunda = api.post(URL_SOLICITAR, _cuerpo_solicitud(), format="json")
    assert segunda.status_code == 429
    assert segunda.json()["code"] == "TOO_MANY_REQUESTS"


def test_rechazar_deja_la_sesion_original_intacta(api, vinculo_en_directorio):
    """El apoderado dice que no y su equipo sigue funcionando."""
    token_a = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json").json()[
        "session_token"
    ]
    solicitud = api.post(URL_SOLICITAR, _cuerpo_solicitud(), format="json")

    rechazo = api.post(
        _url_transferencia(solicitud.json()["id"], "/reject"), **con_bearer(token_a)
    )

    assert rechazo.status_code == 204
    assert TransferenciaSesion.objects.get().estado == TRANSFERENCIA_RECHAZADA
    assert SesionActiva.objects.get().estado == SESION_ACTIVA
    assert api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_B), format="json").status_code == 409


def test_una_credencial_erronea_no_puede_pedir_traspaso(api, vinculo_en_directorio):
    """La solicitud exige la misma credencial que el login."""
    api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")

    respuesta = api.post(
        URL_SOLICITAR,
        {"telefono": TELEFONO, "documento_estudiante": "00000000", "device_id": DEVICE_B},
        format="json",
    )

    assert respuesta.status_code == 404
    assert respuesta.json()["code"] == "STUDENT_LINK_NOT_FOUND"
    assert not TransferenciaSesion.objects.exists()


def test_otro_apoderado_no_puede_aprobar_una_transferencia_ajena(api, vinculo_en_directorio, db):
    """Solo el dueno de la sesion activa decide sobre su traspaso."""
    from apps.cuentas.models import Apoderado
    from apps.cuentas.tokens import emitir_session_token
    from tests.conftest import crear_sesion

    api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    solicitud = api.post(URL_SOLICITAR, _cuerpo_solicitud(), format="json")

    intruso = Apoderado.objects.create(telefono="+51911111111")
    sesion_intruso = crear_sesion(intruso, "device-intruso")
    token_intruso, _ = emitir_session_token(
        intruso.pk, sesion_intruso.jti, sesion_intruso.device_id
    )

    respuesta = api.post(
        _url_transferencia(solicitud.json()["id"], "/approve"), **con_bearer(token_intruso)
    )

    assert respuesta.status_code == 401
    assert TransferenciaSesion.objects.get().estado == TRANSFERENCIA_PENDIENTE
