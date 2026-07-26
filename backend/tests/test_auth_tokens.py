"""Pruebas del modelo de dos tokens (SRS 14.1).

Lo que se comprueba aqui es la separacion de responsabilidades entre el
`session_token` y el `data_token`. Si esa frontera se difumina, un token de 10
dias acabaria abriendo endpoints de negocio y toda la vida corta del token de
datos dejaria de servir para nada.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone as zona_utc

import pytest
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory
from rest_framework.views import APIView

from apps.cuentas import tokens
from apps.cuentas.authentication import DataTokenAuthentication
from apps.cuentas.models import SESION_REVOCADA, SesionActiva
from apps.cuentas.permissions import EsApoderadoConDataToken
from tests.conftest import DEVICE_A, con_bearer, crear_sesion, cuerpo_login

URL_LOGIN = "/v0.1/auth/login"
URL_REFRESH = "/v0.1/auth/refresh-data"
URL_RENEW = "/v0.1/auth/renew-session"
URL_LOGOUT = "/v0.1/auth/logout"

pytestmark = pytest.mark.django_db


class VistaDeNegocioFalsa(APIView):
    """Endpoint de negocio de mentira: exige `data_token`, como los reales."""

    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    def get(self, request):
        """Devuelve el id del apoderado autenticado."""
        return Response({"apoderado_id": request.apoderado.pk})


def _entrar(api, vinculo) -> dict:
    """Hace login y devuelve el cuerpo de la respuesta."""
    respuesta = api.post(URL_LOGIN, cuerpo_login(), format="json")
    assert respuesta.status_code == 200
    return respuesta.json()


# ---------------------------------------------------------------------------
# refresh-data
# ---------------------------------------------------------------------------

def test_data_token_vencido_con_sesion_viva_se_renueva(api, vinculo_en_directorio, settings):
    """La caducidad del token corto es transparente para el usuario."""
    sesion = _entrar(api, vinculo_en_directorio)

    # Un data_token emitido en el pasado ya no vale.
    vencido, _ = tokens.emitir_data_token(
        1,
        tokens.decodificar(sesion["session_token"], tokens.TIPO_SESION)["jti"],
        emitido_en=datetime.now(tz=zona_utc.utc) - timedelta(minutes=settings.DATA_TOKEN_MINUTES + 5),
    )
    peticion = APIRequestFactory().get("/negocio", **con_bearer(vencido))
    assert VistaDeNegocioFalsa.as_view()(peticion).status_code == 401

    # Con el session_token vivo, refresh-data entrega uno nuevo y ese si entra.
    respuesta = api.post(URL_REFRESH, **con_bearer(sesion["session_token"]))
    assert respuesta.status_code == 200
    assert set(respuesta.json()) == {"data_token", "data_expira_en"}

    nuevo = respuesta.json()["data_token"]
    peticion = APIRequestFactory().get("/negocio", **con_bearer(nuevo))
    assert VistaDeNegocioFalsa.as_view()(peticion).status_code == 200


def test_refresh_data_con_session_token_revocado(api, vinculo_en_directorio):
    """Cerrar sesion invalida el session_token al instante: 410, no 200."""
    sesion = _entrar(api, vinculo_en_directorio)

    assert api.post(URL_LOGOUT, **con_bearer(sesion["session_token"])).status_code == 204
    assert SesionActiva.objects.get().estado == SESION_REVOCADA

    respuesta = api.post(URL_REFRESH, **con_bearer(sesion["session_token"]))
    assert respuesta.status_code in (401, 410)
    assert respuesta.json()["code"] in ("UNAUTHENTICATED", "SESSION_EXPIRED")


def test_refresh_data_sin_token_devuelve_401(api, vinculo_en_directorio):
    """Sin credencial no se pasa: el permiso por defecto deniega."""
    assert api.post(URL_REFRESH).status_code == 401


# ---------------------------------------------------------------------------
# Separacion de tipos de token
# ---------------------------------------------------------------------------

def test_un_session_token_no_sirve_para_un_endpoint_de_negocio(api, vinculo_en_directorio):
    """El token de 10 dias solo abre `/auth/*`."""
    sesion = _entrar(api, vinculo_en_directorio)

    peticion = APIRequestFactory().get("/negocio", **con_bearer(sesion["session_token"]))
    respuesta = VistaDeNegocioFalsa.as_view()(peticion)

    assert respuesta.status_code == 401
    assert respuesta.data["code"] == "UNAUTHENTICATED"


def test_un_data_token_no_sirve_para_renovar_la_sesion(api, vinculo_en_directorio):
    """El token de datos no puede prolongar la vida de la sesion."""
    sesion = _entrar(api, vinculo_en_directorio)

    respuesta = api.post(URL_RENEW, **con_bearer(sesion["data_token"]))

    assert respuesta.status_code == 401
    assert respuesta.json()["code"] == "UNAUTHENTICATED"


def test_decodificar_exige_el_tipo_correcto():
    """`decodificar` es el punto unico donde se comprueba el claim `typ`."""
    from apps.common.errors import Unauthenticated

    session_token, _ = tokens.emitir_session_token(1, "3f1a2b3c-0000-4000-8000-000000000001", DEVICE_A)
    data_token, _ = tokens.emitir_data_token(1, "3f1a2b3c-0000-4000-8000-000000000001")

    assert tokens.decodificar(session_token, tokens.TIPO_SESION)["typ"] == "session"
    assert tokens.decodificar(data_token, tokens.TIPO_DATOS)["typ"] == "data"

    with pytest.raises(Unauthenticated):
        tokens.decodificar(session_token, tokens.TIPO_DATOS)
    with pytest.raises(Unauthenticated):
        tokens.decodificar(data_token, tokens.TIPO_SESION)


def test_un_token_con_firma_ajena_se_rechaza(settings):
    """La firma se valida siempre: no basta con que el JSON tenga buena pinta."""
    import jwt

    from apps.common.errors import Unauthenticated

    ajeno = jwt.encode(
        {
            "sub": "1",
            "typ": "session",
            "jti": "3f1a2b3c-0000-4000-8000-000000000001",
            "iat": 0,
            "exp": 9999999999,
        },
        "otra-clave-distinta-igual-de-larga-que-la-buena-para-firmar-jwt!",
        algorithm="HS256",
    )
    with pytest.raises(Unauthenticated):
        tokens.decodificar(ajeno, tokens.TIPO_SESION)


# ---------------------------------------------------------------------------
# renew-session (RF-A07)
# ---------------------------------------------------------------------------

def test_fuera_de_la_ventana_no_se_rota_el_token(api, vinculo_en_directorio):
    """Recien creada la sesion, renovar devuelve el mismo `session_token`."""
    sesion = _entrar(api, vinculo_en_directorio)

    respuesta = api.post(URL_RENEW, **con_bearer(sesion["session_token"]))

    assert respuesta.status_code == 200
    assert respuesta.json()["session_token"] == sesion["session_token"]


def test_dentro_de_la_ventana_se_rota_el_token(api, vinculo_en_directorio, settings):
    """Cerca del vencimiento si se emite un token nuevo con otro `jti`."""
    sesion = _entrar(api, vinculo_en_directorio)
    fila = SesionActiva.objects.get()
    jti_original = fila.jti

    # Se coloca la expiracion dentro de la ventana incluso con el jitter maximo.
    from django.utils import timezone

    SesionActiva.objects.filter(pk=fila.pk).update(expira_en=timezone.now() + timedelta(minutes=30))

    respuesta = api.post(URL_RENEW, **con_bearer(sesion["session_token"]))

    assert respuesta.status_code == 200
    assert respuesta.json()["session_token"] != sesion["session_token"]

    fila.refresh_from_db()
    assert fila.jti != jti_original
    assert SesionActiva.objects.count() == 1


def test_el_jitter_de_renovacion_es_estable_por_cuenta():
    """RF-A07: el escalonado no puede cambiar entre llamadas de la misma cuenta."""
    from apps.cuentas.services import _jitter_renovacion_segundos

    valores = {_jitter_renovacion_segundos(7) for _ in range(5)}
    assert len(valores) == 1
    assert 0 <= valores.pop() < 12 * 3600
    assert _jitter_renovacion_segundos(7) != _jitter_renovacion_segundos(8)


# ---------------------------------------------------------------------------
# Estado de la cuenta
# ---------------------------------------------------------------------------

def test_una_cuenta_suspendida_no_puede_refrescar(api, vinculo_en_directorio):
    """RF-J01: la suspension corta el acceso sin esperar a que caduque nada."""
    from apps.cuentas import suspension
    from apps.cuentas.models import Apoderado

    sesion = _entrar(api, vinculo_en_directorio)
    suspension.suspender(Apoderado.objects.get(), "Motivo de prueba", actor="admin")

    respuesta = api.post(URL_REFRESH, **con_bearer(sesion["session_token"]))

    # La suspension tambien revoca la sesion, asi que llega antes el 410.
    assert respuesta.status_code in (403, 410)
    assert respuesta.json()["code"] in ("ACCOUNT_SUSPENDED", "SESSION_EXPIRED")


def test_forzar_cierre_de_sesion_deja_entrar_a_otro_equipo(api, vinculo_en_directorio, apoderado):
    """RF-B04: la via de escape cuando el apoderado perdio el dispositivo."""
    from apps.cuentas import suspension

    crear_sesion(apoderado, "device-perdido")
    assert suspension.forzar_cierre_sesion(apoderado, actor="admin") == 1

    respuesta = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    assert respuesta.status_code == 200
