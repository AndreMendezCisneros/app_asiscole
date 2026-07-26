"""Circuit breaker por colegio (SRS 7.8).

Un colegio caido no puede penalizar cada login del resto. Tras
`CIRCUIT_BREAKER_FAILURES` fallos consecutivos el colegio se salta durante
`CIRCUIT_BREAKER_COOLDOWN_SECONDS`; pasado ese plazo se deja pasar una sola
sonda antes de volver a confiar en el.

Estados:

* `cerrado`: se consulta con normalidad.
* `abierto`: se salta sin intentar la conexion. El resolvedor lo cuenta como
  colegio no verificado, asi que un login que no encuentre nada respondera 503
  en lugar de un 404 enganoso.
* `semiabierto`: el enfriamiento termino. La primera peticion que llega pasa
  como sonda; si funciona el circuito se cierra, si falla se vuelve a abrir.

El estado vive en la cache (Redis en produccion), compartido por todos los
procesos de gunicorn y por los workers de Celery.
"""

from __future__ import annotations

import logging

from django.conf import settings
from django.core.cache import cache

logger = logging.getLogger("asiscole.directorio.circuito")

ESTADO_CERRADO = "cerrado"
ESTADO_ABIERTO = "abierto"
ESTADO_SEMIABIERTO = "semiabierto"

_PREFIJO = "circuito"


def _clave_fallos(tenant_id: str) -> str:
    return f"{_PREFIJO}:fallos:{tenant_id}"


def _clave_apertura(tenant_id: str) -> str:
    return f"{_PREFIJO}:abierto:{tenant_id}"


def _clave_sonda(tenant_id: str) -> str:
    return f"{_PREFIJO}:sonda:{tenant_id}"


def _umbral() -> int:
    return max(1, int(settings.CIRCUIT_BREAKER_FAILURES))


def _enfriamiento() -> int:
    return max(1, int(settings.CIRCUIT_BREAKER_COOLDOWN_SECONDS))


def fallos_actuales(tenant_id: str) -> int:
    """Devuelve el contador de fallos consecutivos del colegio."""
    return int(cache.get(_clave_fallos(tenant_id)) or 0)


def estado(tenant_id: str) -> str:
    """Devuelve el estado del circuito de un colegio.

    Args:
        tenant_id: Identificador del colegio.

    Returns:
        `cerrado`, `abierto` o `semiabierto`.
    """
    if cache.get(_clave_apertura(tenant_id)):
        return ESTADO_ABIERTO
    if fallos_actuales(tenant_id) >= _umbral():
        # El contador sigue alto pero la marca de apertura ya expiro: toca sonda.
        return ESTADO_SEMIABIERTO
    return ESTADO_CERRADO


def permite_intentar(tenant_id: str) -> bool:
    """Indica si se puede consultar la BD de ese colegio ahora mismo.

    En `semiabierto` solo la primera llamada de cada ventana de enfriamiento
    obtiene permiso: asi una tormenta de logins no se convierte en una tormenta
    de conexiones contra un colegio que sigue caido.
    """
    situacion = estado(tenant_id)

    if situacion == ESTADO_CERRADO:
        return True

    if situacion == ESTADO_ABIERTO:
        logger.debug("circuito_salta_colegio", extra={"tenant": tenant_id, "estado": situacion})
        return False

    # Semiabierto: `add` es atomico y solo lo gana un proceso.
    concedida = bool(cache.add(_clave_sonda(tenant_id), 1, timeout=_enfriamiento()))
    logger.info(
        "circuito_sonda",
        extra={"tenant": tenant_id, "estado": situacion, "concedida": concedida},
    )
    return concedida


def registrar_exito(tenant_id: str) -> None:
    """Cierra el circuito: el colegio volvio a responder."""
    situacion = estado(tenant_id)
    cache.delete_many([_clave_fallos(tenant_id), _clave_apertura(tenant_id), _clave_sonda(tenant_id)])
    if situacion != ESTADO_CERRADO:
        logger.info(
            "circuito_cerrado",
            extra={"tenant": tenant_id, "estado_anterior": situacion, "estado": ESTADO_CERRADO},
        )


def registrar_fallo(tenant_id: str) -> int:
    """Suma un fallo y abre el circuito si se alcanzo el umbral.

    Returns:
        El numero de fallos consecutivos acumulados.
    """
    clave = _clave_fallos(tenant_id)
    # No se usa `incr`: si la clave no existe algunos backends lanzan ValueError.
    fallos = fallos_actuales(tenant_id) + 1
    # El contador vive al menos lo que dura un enfriamiento completo.
    cache.set(clave, fallos, timeout=_enfriamiento() * 2)

    if fallos >= _umbral():
        cache.set(_clave_apertura(tenant_id), 1, timeout=_enfriamiento())
        cache.delete(_clave_sonda(tenant_id))
        logger.warning(
            "circuito_abierto",
            extra={
                "tenant": tenant_id,
                "estado": ESTADO_ABIERTO,
                "fallos": fallos,
                "enfriamiento_s": _enfriamiento(),
            },
        )
    else:
        logger.info(
            "circuito_fallo",
            extra={"tenant": tenant_id, "estado": ESTADO_CERRADO, "fallos": fallos},
        )
    return fallos


def reiniciar(tenant_id: str) -> None:
    """Borra todo el estado del circuito de un colegio (operacion manual)."""
    cache.delete_many([_clave_fallos(tenant_id), _clave_apertura(tenant_id), _clave_sonda(tenant_id)])


def metricas() -> dict[str, str]:
    """Devuelve el estado de cada colegio configurado, para observabilidad.

    Returns:
        Diccionario `tenant_id -> estado`. Solo metadatos tecnicos: no lleva
        ningun dato personal, asi que es seguro volcarlo a un log.
    """
    return {tenant_id: estado(tenant_id) for tenant_id in settings.SCHOOL_TENANTS}
