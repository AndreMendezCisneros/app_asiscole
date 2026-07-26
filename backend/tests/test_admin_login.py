"""Pruebas del login de administrador (RF-B01).

La contrasena se valida contra `usuarios.password_hash` de la BD del colegio,
que es bcrypt generado con `extensions.crypt`. La BD del colegio no se toca ni
en pruebas: se simula la unica consulta que el canal le hace.
"""

from __future__ import annotations

import bcrypt
import pytest

from apps.cuentas import services
from apps.cuentas.models import SESION_ACTIVA, Apoderado, SesionActiva
from apps.cuentas.tokens import TIPO_SESION, decodificar
from tests.conftest import DEVICE_A, DEVICE_B, TENANT

URL_ADMIN_LOGIN = "/v0.1/auth/admin/login"

pytestmark = pytest.mark.django_db

PASSWORD = "Contrasena-Segura-1"


def _hash(password: str = PASSWORD) -> str:
    """Genera un hash bcrypt con el mismo formato `$2...` que usa el colegio."""
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=4)).decode("ascii")


class _CursorFalso:
    """Cursor de mentira que devuelve siempre la misma fila de `usuarios`."""

    def __init__(self, fila):
        self._fila = fila

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, sql, parametros=None):
        """Acepta la consulta sin ejecutarla."""

    def fetchone(self):
        """Devuelve la fila configurada."""
        return self._fila


def _simular_usuario(monkeypatch, fila) -> None:
    """Hace que la consulta a la BD del colegio devuelva `fila`."""

    class _Conexion:
        def cursor(self):
            return _CursorFalso(fila)

    monkeypatch.setattr(services, "connections", {f"colegio_{TENANT}": _Conexion()})


def _cuerpo(**extra) -> dict:
    cuerpo = {
        "usuario": "jperez",
        "password": PASSWORD,
        "device_id": DEVICE_A,
        "tenant_id": TENANT,
    }
    cuerpo.update(extra)
    return cuerpo


def test_login_de_administrador_emite_sesion(api, colegios, monkeypatch):
    """Credencial correcta y rol permitido: sesion con el rol en el token."""
    _simular_usuario(monkeypatch, (7, _hash(), "Director", True, "Juana Perez"))

    respuesta = api.post(URL_ADMIN_LOGIN, _cuerpo(), format="json")

    assert respuesta.status_code == 200
    claims = decodificar(respuesta.json()["session_token"], TIPO_SESION)
    assert claims["role"] == "Director"

    # La cuenta se guarda con una identidad sintetica, no con un telefono.
    cuenta = Apoderado.objects.get()
    assert cuenta.telefono == f"admin:{TENANT}:7"
    assert cuenta.es_administrador is True
    assert respuesta.json()["perfil"]["telefono"] == "administrador"


def test_contrasena_incorrecta_devuelve_401(api, colegios, monkeypatch):
    """Ni se confirma que el usuario exista."""
    _simular_usuario(monkeypatch, (7, _hash(), "Director", True, "Juana Perez"))

    respuesta = api.post(URL_ADMIN_LOGIN, _cuerpo(password="otra-cosa"), format="json")

    assert respuesta.status_code == 401
    assert respuesta.json()["code"] == "UNAUTHENTICATED"
    assert not SesionActiva.objects.exists()


def test_un_rol_sin_permiso_no_entra(api, colegios, monkeypatch):
    """Solo `Admin`, `Director` y `Supervisor`: un Tutor no usa este canal."""
    _simular_usuario(monkeypatch, (7, _hash(), "Tutor", True, "Juana Perez"))

    respuesta = api.post(URL_ADMIN_LOGIN, _cuerpo(), format="json")

    assert respuesta.status_code == 401
    assert not SesionActiva.objects.exists()


def test_un_usuario_inactivo_no_entra(api, colegios, monkeypatch):
    """`usuarios.activo = false` cierra la puerta igual que una clave mala."""
    _simular_usuario(monkeypatch, (7, _hash(), "Admin", False, "Juana Perez"))

    assert api.post(URL_ADMIN_LOGIN, _cuerpo(), format="json").status_code == 401


def test_un_colegio_desconocido_devuelve_401(api, colegios, monkeypatch):
    """El `tenant_id` del cuerpo se contrasta con los colegios configurados."""
    _simular_usuario(monkeypatch, (7, _hash(), "Admin", True, "Juana Perez"))

    respuesta = api.post(URL_ADMIN_LOGIN, _cuerpo(tenant_id="colegio_inventado"), format="json")

    assert respuesta.status_code == 401


def test_el_administrador_tambien_tiene_sesion_unica(api, colegios, monkeypatch):
    """RF-B01: la misma politica de un solo dispositivo."""
    _simular_usuario(monkeypatch, (7, _hash(), "Admin", True, "Juana Perez"))

    assert api.post(URL_ADMIN_LOGIN, _cuerpo(), format="json").status_code == 200
    segundo = api.post(URL_ADMIN_LOGIN, _cuerpo(device_id=DEVICE_B), format="json")

    assert segundo.status_code == 409
    assert segundo.json()["code"] == "SESSION_ALREADY_ACTIVE"
    assert SesionActiva.objects.filter(estado=SESION_ACTIVA).count() == 1


def test_solo_se_aceptan_hashes_bcrypt():
    """Un `password_hash` que no sea bcrypt nunca valida."""
    assert services._verificar_bcrypt(PASSWORD, _hash()) is True
    assert services._verificar_bcrypt(PASSWORD, "md5:loquesea") is False
    assert services._verificar_bcrypt(PASSWORD, "") is False
