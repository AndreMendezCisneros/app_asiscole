"""Limites de intentos del canal (SRS 14.3, ADR-07).

El canal no tiene OTP en la version 1: la unica barrera contra quien conozca un
documento de estudiante y un telefono son estos contadores. Se llevan en la
cache (Redis en produccion), compartidos por todos los procesos:

* `LOGIN_MAX_ATTEMPTS` fallos por credencial (telefono + documento) dentro de
  `LOGIN_ATTEMPT_WINDOW_MINUTES` disparan un bloqueo de `LOGIN_LOCKOUT_MINUTES`.
* El mismo limite se aplica por IP, para que probar documentos distintos contra
  el mismo telefono tampoco salga gratis.
* `TRANSFER_MAX_PER_HOUR` solicitudes de traspaso por cuenta y hora.

PRIVACIDAD (Ley N.o 29733): la clave de la cache y la columna
`asis_intento_login.clave` guardan el hash de `apps.common.phone.hash_credencial`,
nunca el telefono ni el `codigo_barras`. La IP tambien se hashea antes de
convertirse en clave.
"""

from __future__ import annotations

import hashlib
import logging

from django.conf import settings
from django.core.cache import cache

from apps.common.errors import AccountLocked, TooManyRequests
from apps.common.phone import hash_credencial
from apps.cuentas.models import IntentoLogin

logger = logging.getLogger("asiscole.cuentas.limites")

_PREFIJO = "limite"


def clave_credencial(telefono: str, documento: str) -> str:
    """Devuelve el hash de la credencial que identifica el intento."""
    return hash_credencial(telefono, documento)


def _hash_ip(ip: str) -> str:
    """Hashea la IP: tambien es un dato personal y no hace falta en claro."""
    return hashlib.sha256((ip or "").encode("utf-8")).hexdigest()[:32]


def _clave_fallos(credencial: str) -> str:
    return f"{_PREFIJO}:login:fallos:{credencial}"


def _clave_bloqueo(credencial: str) -> str:
    return f"{_PREFIJO}:login:bloqueo:{credencial}"


def _clave_fallos_ip(ip_hash: str) -> str:
    return f"{_PREFIJO}:login:fallos_ip:{ip_hash}"


def _clave_bloqueo_ip(ip_hash: str) -> str:
    return f"{_PREFIJO}:login:bloqueo_ip:{ip_hash}"


def _clave_transferencias(apoderado_id: int) -> str:
    return f"{_PREFIJO}:transferencia:{apoderado_id}"


def _ventana_segundos() -> int:
    return max(1, int(settings.LOGIN_ATTEMPT_WINDOW_MINUTES) * 60)


def _bloqueo_segundos() -> int:
    return max(1, int(settings.LOGIN_LOCKOUT_MINUTES) * 60)


def _maximo_intentos() -> int:
    return max(1, int(settings.LOGIN_MAX_ATTEMPTS))


def _sumar(clave: str, ttl: int) -> int:
    """Incrementa un contador con ventana deslizante simple."""
    # No se usa `cache.incr`: si la clave no existe algunos backends fallan.
    actual = int(cache.get(clave) or 0) + 1
    cache.set(clave, actual, timeout=ttl)
    return actual


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------

def verificar_login(credencial: str, ip: str | None = None) -> None:
    """Comprueba que la credencial y la IP no esten bloqueadas.

    Args:
        credencial: Hash devuelto por `clave_credencial`.
        ip: IP de origen de la peticion, si se conoce.

    Raises:
        AccountLocked: Hay un bloqueo temporal vigente por intentos fallidos.
    """
    if cache.get(_clave_bloqueo(credencial)):
        logger.info("login_bloqueado", extra={"motivo": "credencial"})
        raise AccountLocked()

    if ip and cache.get(_clave_bloqueo_ip(_hash_ip(ip))):
        logger.info("login_bloqueado", extra={"motivo": "ip"})
        raise AccountLocked()


def registrar_fallo_login(credencial: str, ip: str | None = None) -> None:
    """Anota un intento fallido y bloquea si se alcanzo el limite.

    Deja rastro en `asis_intento_login` (solo el hash) y actualiza los
    contadores de la cache.
    """
    IntentoLogin.objects.create(clave=credencial, ip=ip or None, exitoso=False)

    fallos = _sumar(_clave_fallos(credencial), _ventana_segundos())
    if fallos >= _maximo_intentos():
        cache.set(_clave_bloqueo(credencial), 1, timeout=_bloqueo_segundos())
        cache.delete(_clave_fallos(credencial))
        logger.warning(
            "login_bloqueo_activado",
            extra={"motivo": "credencial", "minutos": settings.LOGIN_LOCKOUT_MINUTES},
        )

    if ip:
        ip_hash = _hash_ip(ip)
        fallos_ip = _sumar(_clave_fallos_ip(ip_hash), _ventana_segundos())
        if fallos_ip >= _maximo_intentos():
            cache.set(_clave_bloqueo_ip(ip_hash), 1, timeout=_bloqueo_segundos())
            cache.delete(_clave_fallos_ip(ip_hash))
            logger.warning(
                "login_bloqueo_activado",
                extra={"motivo": "ip", "minutos": settings.LOGIN_LOCKOUT_MINUTES},
            )


def registrar_exito_login(credencial: str, ip: str | None = None) -> None:
    """Anota un login correcto y limpia los contadores de esa credencial."""
    IntentoLogin.objects.create(clave=credencial, ip=ip or None, exitoso=True)
    cache.delete_many([_clave_fallos(credencial), _clave_bloqueo(credencial)])
    if ip:
        cache.delete(_clave_fallos_ip(_hash_ip(ip)))


def limpiar_login(credencial: str, ip: str | None = None) -> None:
    """Borra el bloqueo de una credencial (uso administrativo y pruebas)."""
    claves = [_clave_fallos(credencial), _clave_bloqueo(credencial)]
    if ip:
        ip_hash = _hash_ip(ip)
        claves.extend([_clave_fallos_ip(ip_hash), _clave_bloqueo_ip(ip_hash)])
    cache.delete_many(claves)


# ---------------------------------------------------------------------------
# Transferencia de sesion
# ---------------------------------------------------------------------------

def verificar_transferencias(apoderado_id: int) -> None:
    """Comprueba el limite de solicitudes de traspaso por hora (RF-A09).

    Raises:
        TooManyRequests: Se supero `TRANSFER_MAX_PER_HOUR`.
    """
    usadas = int(cache.get(_clave_transferencias(apoderado_id)) or 0)
    if usadas >= max(1, int(settings.TRANSFER_MAX_PER_HOUR)):
        logger.info("transferencia_limite", extra={"apoderado_id": apoderado_id})
        raise TooManyRequests()


def registrar_transferencia(apoderado_id: int) -> int:
    """Suma una solicitud de traspaso a la ventana de una hora.

    Returns:
        Cuantas solicitudes lleva el apoderado en la ventana.
    """
    return _sumar(_clave_transferencias(apoderado_id), 3600)
