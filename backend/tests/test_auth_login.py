"""Pruebas del login del apoderado (RF-A01 a RF-A05, ADR-06, ADR-07).

Cubren el nucleo del canal: que la credencial se compruebe de forma estricta,
que la sesion sea unica de verdad y que los limites de intentos funcionen.
"""

from __future__ import annotations

import pytest
from django.utils import timezone

from apps.cuentas import services
from apps.cuentas.models import (
    CUENTA_SUSPENDIDA,
    SESION_ACTIVA,
    Apoderado,
    IntentoLogin,
    PushToken,
    SesionActiva,
)
from apps.cuentas.tokens import TIPO_DATOS, TIPO_SESION, decodificar
from tests.conftest import DEVICE_A, DEVICE_B, DOCUMENTO, TELEFONO, cuerpo_login

URL_LOGIN = "/v0.1/auth/login"

pytestmark = pytest.mark.django_db


def test_login_correcto_emite_ambos_tokens_y_crea_la_sesion(api, vinculo_en_directorio):
    """El caso feliz: dos tokens, una sesion y el perfil del contrato."""
    respuesta = api.post(URL_LOGIN, cuerpo_login(push_token="fcm-123", plataforma="android"), format="json")

    assert respuesta.status_code == 200
    cuerpo = respuesta.json()
    assert set(cuerpo) == {
        "session_token",
        "session_expira_en",
        "data_token",
        "data_expira_en",
        "perfil",
    }

    claims_sesion = decodificar(cuerpo["session_token"], TIPO_SESION)
    claims_datos = decodificar(cuerpo["data_token"], TIPO_DATOS)
    assert claims_sesion["device_id"] == DEVICE_A
    assert claims_datos["sid"] == claims_sesion["jti"]
    assert claims_datos["scope"] == "student_read"

    sesion = SesionActiva.objects.get()
    assert sesion.estado == SESION_ACTIVA
    assert str(sesion.jti) == claims_sesion["jti"]
    assert sesion.device_id == DEVICE_A

    # El perfil enmascara el telefono y apunta al estudiante del documento usado.
    perfil = cuerpo["perfil"]
    assert perfil["telefono"] != TELEFONO
    assert perfil["telefono"].startswith("+51")
    assert perfil["estudiante_activo_id"] == vinculo_en_directorio.id_estudiante

    assert PushToken.objects.filter(activo=True, device_id=DEVICE_A).count() == 1
    assert IntentoLogin.objects.filter(exitoso=True).count() == 1


def test_documento_que_no_coincide_devuelve_404(api, vinculo_en_directorio):
    """El telefono existe pero el documento no: 404 sin decir cual fallo."""
    respuesta = api.post(URL_LOGIN, cuerpo_login(documento_estudiante="99999999"), format="json")

    assert respuesta.status_code == 404
    cuerpo = respuesta.json()
    assert cuerpo["code"] == "STUDENT_LINK_NOT_FOUND"
    for pista in ("teléfono", "telefono", "documento"):
        assert pista not in cuerpo["message"].lower()
    assert not SesionActiva.objects.exists()


def test_telefono_desconocido_devuelve_404(api, db, colegios, monkeypatch):
    """Sin vinculo en ningun sitio y con los colegios sanos: 404, no 503."""
    monkeypatch.setattr(
        "apps.directorio.repositorio.consultar_colegio", lambda tenant, telefono: []
    )
    respuesta = api.post(URL_LOGIN, cuerpo_login(telefono="+51900000000"), format="json")

    assert respuesta.status_code == 404
    assert respuesta.json()["code"] == "STUDENT_LINK_NOT_FOUND"


def test_telefono_invalido_devuelve_400(api, vinculo_en_directorio):
    """Un telefono que no es un numero se rechaza antes de tocar el directorio."""
    respuesta = api.post(URL_LOGIN, cuerpo_login(telefono="no-soy-un-telefono"), format="json")

    assert respuesta.status_code == 400
    assert respuesta.json()["code"] == "VALIDATION_ERROR"


def test_segundo_dispositivo_devuelve_409_y_la_sesion_original_sigue_intacta(
    api, vinculo_en_directorio
):
    """ADR-06: el segundo equipo se deniega, nunca reemplaza a la sesion viva."""
    primero = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    assert primero.status_code == 200
    sesion_original = SesionActiva.objects.get()

    segundo = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_B), format="json")

    assert segundo.status_code == 409
    assert segundo.json()["code"] == "SESSION_ALREADY_ACTIVE"

    sesion_original.refresh_from_db()
    assert sesion_original.estado == SESION_ACTIVA
    assert sesion_original.device_id == DEVICE_A
    assert SesionActiva.objects.count() == 1
    # El session_token del primer equipo sigue sirviendo.
    assert str(sesion_original.jti) == decodificar(primero.json()["session_token"], TIPO_SESION)["jti"]


def test_el_mismo_dispositivo_vuelve_a_entrar_sin_409(api, vinculo_en_directorio):
    """Reinstalar la app en el mismo equipo no puede exigir al administrador."""
    primero = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    segundo = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")

    assert segundo.status_code == 200
    assert SesionActiva.objects.count() == 1

    # Se reutiliza la fila pero con un jti nuevo: los tokens viejos mueren.
    jti_viejo = decodificar(primero.json()["session_token"], TIPO_SESION)["jti"]
    jti_nuevo = decodificar(segundo.json()["session_token"], TIPO_SESION)["jti"]
    assert jti_viejo != jti_nuevo
    assert str(SesionActiva.objects.get().jti) == jti_nuevo


def test_dos_logins_concurrentes_solo_uno_gana(api, vinculo_en_directorio, monkeypatch):
    """El indice unico parcial resuelve la carrera entre dos logins simultaneos.

    Se simula el intercalado peor posible: los dos procesos comprueban a la vez
    que no hay sesion activa y los dos intentan insertarla. La segunda insercion
    choca contra `asis_uniq_sesion_activa` y el servicio traduce el
    `IntegrityError` en el mismo 409 que ve un segundo dispositivo.
    """
    primero = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    assert primero.status_code == 200

    # A partir de aqui el servicio "no ve" la sesion que si esta en la BD.
    monkeypatch.setattr(services, "_sesion_activa_de", lambda apoderado: None)
    segundo = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_B), format="json")

    assert segundo.status_code == 409
    assert segundo.json()["code"] == "SESSION_ALREADY_ACTIVE"
    assert SesionActiva.objects.filter(estado=SESION_ACTIVA).count() == 1


def test_cuenta_suspendida_devuelve_403(api, vinculo_en_directorio):
    """RF-J03: una cuenta suspendida tampoco puede iniciar sesion de nuevo."""
    Apoderado.objects.create(
        telefono=TELEFONO, estado=CUENTA_SUSPENDIDA, motivo_suspension="Uso indebido"
    )

    respuesta = api.post(URL_LOGIN, cuerpo_login(), format="json")

    assert respuesta.status_code == 403
    assert respuesta.json()["code"] == "ACCOUNT_SUSPENDED"
    assert not SesionActiva.objects.exists()


def test_superar_el_limite_de_intentos_devuelve_423(api, vinculo_en_directorio, settings):
    """SRS 14.3: tras `LOGIN_MAX_ATTEMPTS` fallos llega el bloqueo temporal."""
    settings.LOGIN_MAX_ATTEMPTS = 3
    malo = cuerpo_login(documento_estudiante="00000000")

    for _ in range(settings.LOGIN_MAX_ATTEMPTS):
        assert api.post(URL_LOGIN, malo, format="json").status_code == 404

    respuesta = api.post(URL_LOGIN, malo, format="json")
    assert respuesta.status_code == 423
    assert respuesta.json()["code"] == "ACCOUNT_LOCKED"


def test_el_bloqueo_alcanza_al_documento_correcto(api, vinculo_en_directorio, settings):
    """El bloqueo es por credencial, asi que la IP tambien queda frenada."""
    settings.LOGIN_MAX_ATTEMPTS = 2
    for _ in range(2):
        api.post(URL_LOGIN, cuerpo_login(documento_estudiante="00000000"), format="json")

    respuesta = api.post(URL_LOGIN, cuerpo_login(), format="json")
    assert respuesta.status_code == 423


def test_bloqueo_escala_a_diez_minutos_tras_desbloqueo(
    vinculo_en_directorio, settings, monkeypatch
):
    """Tras el primer bloqueo (5 min), el siguiente fallo escala a 10 min."""
    from django.core.cache import cache

    from apps.cuentas import rate_limit

    settings.LOGIN_MAX_ATTEMPTS = 3
    settings.LOGIN_LOCKOUT_MINUTES = 5
    settings.LOGIN_LOCKOUT_ESCALATED_MINUTES = 10
    settings.LOGIN_HARD_MAX_ATTEMPTS = 8
    settings.LOGIN_HARD_LOCKOUT_MINUTES = 1440

    minutos: list[int] = []
    original = rate_limit._activar_bloqueo

    def _espiar(clave_bloqueo, fallos, motivo):
        minutos.append(rate_limit._minutos_bloqueo(fallos))
        original(clave_bloqueo, fallos, motivo)

    monkeypatch.setattr(rate_limit, "_activar_bloqueo", _espiar)

    cred = rate_limit.clave_credencial(TELEFONO, "00000000")

    for _ in range(3):
        rate_limit.registrar_fallo_login(cred)
    assert minutos == [5]

    cache.delete(rate_limit._clave_bloqueo(cred))
    rate_limit.registrar_fallo_login(cred)
    assert minutos == [5, 10]


def test_bloqueo_largo_tras_ocho_fallos_acumulados(
    vinculo_en_directorio, settings, monkeypatch
):
    """~8 fallos acumulados en la ventana disparan el bloqueo de 24 h."""
    from django.core.cache import cache

    from apps.cuentas import rate_limit

    settings.LOGIN_MAX_ATTEMPTS = 3
    settings.LOGIN_LOCKOUT_MINUTES = 5
    settings.LOGIN_LOCKOUT_ESCALATED_MINUTES = 10
    settings.LOGIN_HARD_MAX_ATTEMPTS = 8
    settings.LOGIN_HARD_LOCKOUT_MINUTES = 1440

    minutos: list[int] = []
    original = rate_limit._activar_bloqueo

    def _espiar(clave_bloqueo, fallos, motivo):
        minutos.append(rate_limit._minutos_bloqueo(fallos))
        original(clave_bloqueo, fallos, motivo)

    monkeypatch.setattr(rate_limit, "_activar_bloqueo", _espiar)

    cred = rate_limit.clave_credencial(TELEFONO, "00000000")

    for _ in range(8):
        cache.delete(rate_limit._clave_bloqueo(cred))
        rate_limit.registrar_fallo_login(cred)

    assert 1440 in minutos
    assert minutos[-1] == 1440


def test_los_intentos_no_guardan_datos_personales(api, vinculo_en_directorio):
    """`asis_intento_login.clave` es un hash: nunca el telefono ni el documento."""
    api.post(URL_LOGIN, cuerpo_login(documento_estudiante="00000000"), format="json")

    intento = IntentoLogin.objects.get()
    assert len(intento.clave) == 64
    assert TELEFONO not in intento.clave
    assert DOCUMENTO not in intento.clave
    assert "00000000" not in intento.clave


def test_login_denegado_avisa_al_dispositivo_activo(api, vinculo_en_directorio, monkeypatch):
    """ADR-07: sin OTP, el aviso push al equipo activo es la mitigacion."""
    avisos = []
    monkeypatch.setattr(
        "apps.cuentas.notificaciones.notificar_intento_acceso",
        lambda apoderado, device_id: avisos.append(device_id) or True,
    )

    api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")
    api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_B), format="json")

    assert avisos == [DEVICE_B]


def test_una_sesion_vencida_no_impide_un_login_nuevo(api, vinculo_en_directorio, apoderado):
    """Una sesion caducada libera el indice unico parcial."""
    from tests.conftest import crear_sesion

    sesion = crear_sesion(apoderado, DEVICE_B)
    SesionActiva.objects.filter(pk=sesion.pk).update(expira_en=timezone.now())

    respuesta = api.post(URL_LOGIN, cuerpo_login(device_id=DEVICE_A), format="json")

    assert respuesta.status_code == 200
    assert SesionActiva.objects.filter(estado=SESION_ACTIVA).count() == 1
