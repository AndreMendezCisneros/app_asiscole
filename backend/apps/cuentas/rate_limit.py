"""Limites de intentos del canal (SRS 14.3, ADR-07).

El canal no tiene OTP en la version 1: la unica barrera contra quien conozca un
documento de estudiante y un telefono son estos contadores. Se llevan en la
cache (Redis en produccion), compartidos por todos los procesos:

* Tras `LOGIN_MAX_ATTEMPTS` fallos (por defecto 3) se aplica un bloqueo corto
  de `LOGIN_LOCKOUT_MINUTES` (5 min).
* Si tras el desbloqueo vuelve a fallar (o acumula mas fallos), el siguiente
  bloqueo dura `LOGIN_LOCKOUT_ESCALATED_MINUTES` (10 min).
* Al llegar a `LOGIN_HARD_MAX_ATTEMPTS` fallos acumulados en la ventana
  (`LOGIN_ATTEMPT_WINDOW_MINUTES`), bloqueo largo de
  `LOGIN_HARD_LOCKOUT_MINUTES` (24 h) hasta que expire o un admin limpie.
* El mismo esquema aplica por IP.
* `TRANSFER_MAX_PER_HOUR` solicitudes de traspaso por cuenta y hora.

PRIVACIDAD (Ley N.o 29733): la clave de la cache y la columna
`asis_intento_login.clave` guardan el hash de `apps.common.phone.hash_credencial`,
nunca el telefono ni el `codigo_barras`. La IP tambien se hashea antes de
convertirse en clave.
"""

from __future__ import annotations

import hashlib
import logging
import time

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


def _maximo_intentos() -> int:
    return max(1, int(settings.LOGIN_MAX_ATTEMPTS))


def _maximo_duro() -> int:
    return max(_maximo_intentos(), int(settings.LOGIN_HARD_MAX_ATTEMPTS))


def _minutos_bloqueo(fallos: int) -> int:
    """Elige la duración del bloqueo según fallos acumulados en la ventana."""
    if fallos >= _maximo_duro():
        return max(1, int(settings.LOGIN_HARD_LOCKOUT_MINUTES))
    if fallos > _maximo_intentos():
        return max(1, int(settings.LOGIN_LOCKOUT_ESCALATED_MINUTES))
    return max(1, int(settings.LOGIN_LOCKOUT_MINUTES))


def _debe_bloquear(fallos: int) -> bool:
    return fallos >= _maximo_intentos()


def _cache_es_locmem() -> bool:
    """True si el backend de cache no necesita Redis (tests / runserver)."""
    backend = (settings.CACHES.get("default") or {}).get("BACKEND", "")
    return "locmem" in backend.lower() or "dummy" in backend.lower()


def _asegurar_cache_auth() -> None:
    """Fail-closed: sin cache usable no se permite login (anti fuerza bruta).

    Con `IGNORE_EXCEPTIONS` Redis caído hace que get/set fallen en silencio.
    Aquí se detecta y se responde 429 en lugar de abrir el login.
    """
    if _cache_es_locmem():
        return
    try:
        sonda = f"{_PREFIJO}:probe:{int(time.time() * 1000) % 1_000_000}"
        cache.set(sonda, 1, timeout=5)
        if cache.get(sonda) != 1:
            raise RuntimeError("cache_probe_fallida")
        cache.delete(sonda)
    except Exception as exc:  # noqa: BLE001 — cualquier fallo = denegar
        logger.error("rate_limit_cache_indisponible")
        raise TooManyRequests(
            "El servicio de autenticación no está disponible temporalmente. "
            "Inténtalo más tarde."
        ) from exc


def _sumar(clave: str, ttl: int) -> int:
    """Incrementa un contador con ventana deslizante simple."""
    # No se usa `cache.incr`: si la clave no existe algunos backends fallan.
    actual = int(cache.get(clave) or 0) + 1
    cache.set(clave, actual, timeout=ttl)
    return actual


def _activar_bloqueo(clave_bloqueo: str, fallos: int, motivo: str) -> None:
    minutos = _minutos_bloqueo(fallos)
    hasta = time.time() + (minutos * 60)
    # Guardamos el epoch de fin: permite informar minutos restantes sin PII.
    cache.set(clave_bloqueo, hasta, timeout=max(1, minutos * 60))
    # No se borra el contador de fallos: permite escalar 5→10→24h en la ventana.
    logger.warning(
        "login_bloqueo_activado",
        extra={"motivo": motivo, "minutos": minutos, "fallos": fallos},
    )


def _minutos_restantes(clave_bloqueo: str) -> int | None:
    """Devuelve minutos restantes del bloqueo, o None si no hay bloqueo."""
    valor = cache.get(clave_bloqueo)
    if valor is None:
        return None
    try:
        hasta = float(valor)
    except (TypeError, ValueError):
        return 1
    restantes = int((hasta - time.time()) / 60)
    return max(1, restantes)


def _mensaje_bloqueo(minutos: int | None) -> str:
    if minutos is None:
        return AccountLocked.default_message
    if minutos >= 60:
        horas = max(1, minutos // 60)
        return (
            f"Bloqueamos el acceso temporalmente por varios intentos fallidos. "
            f"Inténtalo en unas {horas} h."
        )
    return (
        f"Bloqueamos el acceso temporalmente por varios intentos fallidos. "
        f"Inténtalo en unos {minutos} min."
    )


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
        TooManyRequests: La cache de limites no responde (fail-closed).
    """
    _asegurar_cache_auth()
    minutos = _minutos_restantes(_clave_bloqueo(credencial))
    if minutos is not None:
        logger.info("login_bloqueado", extra={"motivo": "credencial"})
        raise AccountLocked(_mensaje_bloqueo(minutos))

    if ip:
        minutos_ip = _minutos_restantes(_clave_bloqueo_ip(_hash_ip(ip)))
        if minutos_ip is not None:
            logger.info("login_bloqueado", extra={"motivo": "ip"})
            raise AccountLocked(_mensaje_bloqueo(minutos_ip))


def registrar_fallo_login(credencial: str, ip: str | None = None) -> None:
    """Anota un intento fallido y bloquea si se alcanzo el limite.

    Deja rastro en `asis_intento_login` (solo el hash) y actualiza los
    contadores de la cache. El contador de fallos se conserva tras un bloqueo
    corto para poder escalar la duracion (5 min → 10 min → 24 h).
    """
    _asegurar_cache_auth()
    ip_almacenada = _hash_ip(ip) if ip else None
    IntentoLogin.objects.create(clave=credencial, ip=ip_almacenada, exitoso=False)

    fallos = _sumar(_clave_fallos(credencial), _ventana_segundos())
    if _debe_bloquear(fallos) and not cache.get(_clave_bloqueo(credencial)):
        _activar_bloqueo(_clave_bloqueo(credencial), fallos, "credencial")

    if ip:
        ip_hash = _hash_ip(ip)
        fallos_ip = _sumar(_clave_fallos_ip(ip_hash), _ventana_segundos())
        if _debe_bloquear(fallos_ip) and not cache.get(_clave_bloqueo_ip(ip_hash)):
            _activar_bloqueo(_clave_bloqueo_ip(ip_hash), fallos_ip, "ip")


def registrar_exito_login(credencial: str, ip: str | None = None) -> None:
    """Anota un login correcto y limpia los contadores de esa credencial."""
    _asegurar_cache_auth()
    ip_almacenada = _hash_ip(ip) if ip else None
    IntentoLogin.objects.create(clave=credencial, ip=ip_almacenada, exitoso=True)
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
    _asegurar_cache_auth()
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


# ---------------------------------------------------------------------------
# Endpoints publicos que no son login
# ---------------------------------------------------------------------------

def verificar_publico_por_ip(nombre: str, ip: str | None, *, maximo: int, ventana: int) -> None:
    """Limita un endpoint publico por IP, **fallando abierto**.

    Al contrario que el login, aqui no hay nada que proteger por fuerza bruta:
    solo se evita que alguien lo use de amplificador. Si Redis no responde se
    deja pasar, porque bloquear el arranque de la app por eso seria mucho peor
    que atender unas peticiones de mas.

    Args:
        nombre: Identificador del endpoint, para no mezclar contadores.
        ip: IP de origen; sin ella no se limita nada.
        maximo: Peticiones permitidas en la ventana.
        ventana: Tamano de la ventana, en segundos.

    Raises:
        TooManyRequests: Se supero el limite para esa IP.
    """
    if not ip:
        return
    clave = f"{_PREFIJO}:publico:{nombre}:{_hash_ip(ip)}"
    try:
        usadas = _sumar(clave, max(1, ventana))
    except Exception:  # noqa: BLE001 — fail-open deliberado
        logger.warning("rate_limit_publico_sin_cache", extra={"endpoint": nombre})
        return
    if usadas > max(1, maximo):
        logger.info("rate_limit_publico_excedido", extra={"endpoint": nombre})
        raise TooManyRequests()
