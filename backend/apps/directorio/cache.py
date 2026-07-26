"""Cache en Redis del directorio telefonico (ADR-05).

La clave es `directorio:{telefono_e164}` y el valor la lista de vinculos ya
serializados. El TTL sale de `DIRECTORY_CACHE_TTL_SECONDS` (24 horas por defecto).

Se distingue "no hay entrada" de "hay entrada y esta vacia": `leer_cache`
devuelve `None` en el primer caso y una lista en el segundo. Solo se cachean
resultados con contenido, para que un telefono desconocido no quede congelado
durante un dia si el colegio lo da de alta a los cinco minutos.

Un Redis caido degrada pero no tumba: `django-redis` va con
`IGNORE_EXCEPTIONS`, asi que un fallo se traduce en un miss y el resolvedor
vuelve a la BD.
"""

from __future__ import annotations

import logging

from django.conf import settings
from django.core.cache import cache

from apps.directorio.dto import VinculoDTO

logger = logging.getLogger("asiscole.directorio")

#: Prefijo de la clave. Redis ya anade el KEY_PREFIX global de Django.
PREFIJO_CLAVE = "directorio"


def clave_de(telefono_e164: str) -> str:
    """Construye la clave de Redis de un telefono.

    Args:
        telefono_e164: Telefono ya normalizado. La clave contiene un dato
            personal, por eso jamas se escribe en un log.

    Returns:
        La clave `directorio:{telefono}`.
    """
    return f"{PREFIJO_CLAVE}:{telefono_e164}"


def leer_cache(telefono_e164: str) -> list[VinculoDTO] | None:
    """Lee los vinculos cacheados de un telefono.

    Returns:
        La lista de vinculos si hay entrada, o `None` si es un miss (o si Redis
        no responde, que a efectos del resolvedor es lo mismo).
    """
    crudo = cache.get(clave_de(telefono_e164))
    if crudo is None:
        return None
    if not isinstance(crudo, list):
        # Entrada corrupta o de un formato anterior: se trata como miss.
        logger.warning("directorio_cache_invalida", extra={"tipo": type(crudo).__name__})
        return None
    return [VinculoDTO.desde_dict(item) for item in crudo]


def escribir_cache(telefono_e164: str, vinculos: list[VinculoDTO], ttl: int | None = None) -> None:
    """Cachea los vinculos de un telefono.

    Args:
        telefono_e164: Telefono normalizado.
        vinculos: Vinculos resueltos. Si viene vacio no se escribe nada.
        ttl: Segundos de vida; por defecto `DIRECTORY_CACHE_TTL_SECONDS`.
    """
    if not vinculos:
        return
    segundos = settings.DIRECTORY_CACHE_TTL_SECONDS if ttl is None else ttl
    cache.set(clave_de(telefono_e164), [v.como_dict() for v in vinculos], timeout=segundos)


def invalidar(telefono_e164: str, telefono_anterior: str | None = None) -> None:
    """Borra la entrada de un telefono y, si el contacto cambio, la del viejo.

    Cuando el colegio corrige `telefono_contacto` quedan dos claves sucias: la
    del numero que dejo de tener al estudiante y la del que lo tiene ahora. Se
    borran ambas (ADR-05, apartado de invalidacion).

    Args:
        telefono_e164: Telefono nuevo o unico afectado.
        telefono_anterior: Telefono que tenia el vinculo antes del cambio.
    """
    claves = {clave_de(t) for t in (telefono_e164, telefono_anterior) if t}
    for clave in claves:
        cache.delete(clave)
    logger.debug("directorio_cache_invalidada", extra={"claves": len(claves)})


def invalidar_muchos(telefonos: object) -> int:
    """Invalida un conjunto de telefonos de una vez (lo usa la reconciliacion).

    Args:
        telefonos: Iterable de telefonos en E.164.

    Returns:
        Cuantas claves se borraron.
    """
    unicos = {t for t in telefonos if t}
    for telefono in unicos:
        cache.delete(clave_de(telefono))
    return len(unicos)
