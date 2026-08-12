"""Resolvedor del directorio telefonico (ADR-05, SRS 7.8).

Responde a la pregunta que abre todo el canal: *que estudiantes, y de que
colegio, cuelgan de este telefono*. El orden de busqueda esta pensado para que
el login normal no dependa de que todas las BDs de colegio esten en pie:

1. Redis (`directorio:{telefono}`).
2. `asis_directorio` de la BD central.
3. Las BDs de colegio, todas en paralelo y con timeout corto.
4. Se persiste lo hallado, se cachea y se devuelve.

La distincion del paso 5 es la que evita mentirle al apoderado: si no se
encontro nada **y ademas** algun colegio no pudo verificarse, se responde 503;
si todos respondieron bien y aun asi no hay vinculo, se devuelve lista vacia y
el llamador emite `STUDENT_LINK_NOT_FOUND`. Un 503 solo procede cuando de
verdad no se pudo comprobar.
"""

from __future__ import annotations

import logging
from concurrent.futures import Future, ThreadPoolExecutor, wait
from dataclasses import dataclass, field

from django.conf import settings
from django.db import connections, transaction
from django.utils import timezone

from apps.common.errors import UpstreamSchoolDbUnavailable
from apps.directorio import cache as cache_directorio
from apps.directorio import circuit_breaker, repositorio
from apps.directorio.dto import VinculoDTO
from apps.directorio.models import (
    ORIGEN_AUTOMATICO,
    VINCULO_ACTIVO,
    VINCULO_INACTIVO,
    Directorio,
)

logger = logging.getLogger("asiscole.directorio")

#: Tope de hilos del abanico. Con pocos colegios manda `len(tenants)`.
MAX_HILOS = 16


@dataclass
class ResultadoColegios:
    """Resumen de una ronda de consultas a las BDs de colegio.

    Attributes:
        vinculos: Todo lo hallado, ya mezclado.
        consultados: Colegios que respondieron correctamente.
        fallidos: Colegios que dieron error, timeout o estaban con el circuito
            abierto. Mientras esta lista no este vacia no se puede afirmar que
            un telefono sea desconocido.
    """

    vinculos: list[VinculoDTO] = field(default_factory=list)
    consultados: list[str] = field(default_factory=list)
    fallidos: list[str] = field(default_factory=list)

    @property
    def todos_respondieron(self) -> bool:
        """True si ningun colegio quedo sin verificar."""
        return not self.fallidos


def tenants_configurados() -> list[str]:
    """Devuelve los colegios declarados en `SCHOOL_DATABASES`."""
    return sorted(settings.SCHOOL_TENANTS)


# ---------------------------------------------------------------------------
# Paso 2: la proyeccion de la BD central
# ---------------------------------------------------------------------------

def listar_persistidos(telefono_e164: str, *, solo_activos: bool = True) -> list[VinculoDTO]:
    """Lee los vinculos de `asis_directorio` para un telefono.

    Args:
        telefono_e164: Telefono normalizado.
        solo_activos: Si es True descarta los vinculos dados de baja.

    Returns:
        Los vinculos guardados en la BD central.
    """
    consulta = Directorio.objects.filter(telefono=telefono_e164)
    if solo_activos:
        consulta = consulta.filter(estado_vinculo=VINCULO_ACTIVO)
    return [VinculoDTO.desde_modelo(fila) for fila in consulta.order_by("tenant_id", "id_estudiante")]


# ---------------------------------------------------------------------------
# Paso 3: abanico paralelo contra las BDs de colegio
# ---------------------------------------------------------------------------

def _consultar_colegio_aislado(tenant_id: str, telefono_e164: str) -> list[VinculoDTO]:
    """Consulta un colegio dentro de un hilo del pool.

    Cierra las conexiones al terminar porque las de Django son locales al hilo:
    sin esto cada login dejaria una conexion abierta por colegio.
    """
    try:
        return repositorio.consultar_colegio(tenant_id, telefono_e164)
    finally:
        connections.close_all()


def resolver_en_colegios(telefono_e164: str) -> ResultadoColegios:
    """Pregunta a todos los colegios a la vez, con timeout y circuit breaker.

    El timeout es global de la ronda y no acumulativo: como las consultas corren
    en paralelo, `SCHOOL_DB_TIMEOUT_SECONDS` acota tanto lo que espera cada
    colegio como lo que espera el login completo.

    Args:
        telefono_e164: Telefono normalizado a buscar.

    Returns:
        Un `ResultadoColegios` con lo hallado y con los colegios que no se
        pudieron verificar.
    """
    resultado = ResultadoColegios()
    tenants = tenants_configurados()
    if not tenants:
        return resultado

    disponibles: list[str] = []
    for tenant_id in tenants:
        if circuit_breaker.permite_intentar(tenant_id):
            disponibles.append(tenant_id)
        else:
            # Circuito abierto: no se consulta, pero tampoco se puede afirmar
            # que el telefono no exista en ese colegio.
            resultado.fallidos.append(tenant_id)

    if not disponibles:
        return resultado

    ejecutor = ThreadPoolExecutor(max_workers=min(MAX_HILOS, len(disponibles)))
    try:
        futuros: dict[Future, str] = {
            ejecutor.submit(_consultar_colegio_aislado, tenant_id, telefono_e164): tenant_id
            for tenant_id in disponibles
        }
        terminados, pendientes = wait(futuros, timeout=settings.SCHOOL_DB_TIMEOUT_SECONDS)

        for futuro in terminados:
            tenant_id = futuros[futuro]
            try:
                hallados = futuro.result()
            except Exception:  # noqa: BLE001 — cualquier fallo del colegio se aisla
                circuit_breaker.registrar_fallo(tenant_id)
                resultado.fallidos.append(tenant_id)
                # Sin traza ni excepcion en el log: podria arrastrar el SQL con
                # el telefono. Basta el tenant y el resultado.
                logger.warning("directorio_colegio_error", extra={"tenant": tenant_id})
                continue
            circuit_breaker.registrar_exito(tenant_id)
            resultado.consultados.append(tenant_id)
            resultado.vinculos.extend(hallados)

        for futuro in pendientes:
            tenant_id = futuros[futuro]
            circuit_breaker.registrar_fallo(tenant_id)
            resultado.fallidos.append(tenant_id)
            logger.warning(
                "directorio_colegio_timeout",
                extra={"tenant": tenant_id, "timeout_s": settings.SCHOOL_DB_TIMEOUT_SECONDS},
            )
    finally:
        # No se espera a los hilos rezagados: el login ya tiene su respuesta.
        ejecutor.shutdown(wait=False, cancel_futures=True)

    return resultado


# ---------------------------------------------------------------------------
# Paso 4: persistencia de lo hallado
# ---------------------------------------------------------------------------

def guardar_vinculos(vinculos: list[VinculoDTO], *, origen: str = ORIGEN_AUTOMATICO) -> int:
    """Hace upsert de una lista de vinculos en `asis_directorio`.

    Args:
        vinculos: Vinculos resueltos contra la BD del colegio.
        origen: Como llego el vinculo (`resuelto_automatico` por defecto).

    Returns:
        Cuantas filas se insertaron o actualizaron.
    """
    if not vinculos:
        return 0

    ahora = timezone.now()
    escritas = 0
    with transaction.atomic():
        for vinculo in vinculos:
            Directorio.objects.update_or_create(
                telefono=vinculo.telefono,
                tenant_id=vinculo.tenant_id,
                id_estudiante=vinculo.id_estudiante,
                defaults={
                    "codigo_barras": vinculo.codigo_barras,
                    "nombre_estudiante": vinculo.nombre_estudiante,
                    "grado": vinculo.grado,
                    "seccion": vinculo.seccion,
                    "nivel": vinculo.nivel,
                    "relacion": vinculo.relacion or "apoderado",
                    "origen": origen,
                    "estado_vinculo": vinculo.estado_vinculo or VINCULO_ACTIVO,
                    "sincronizado_en": ahora,
                },
            )
            escritas += 1
    return escritas


# ---------------------------------------------------------------------------
# El resolvedor
# ---------------------------------------------------------------------------

def resolver_vinculos(telefono_e164: str) -> list[VinculoDTO]:
    """Resuelve los vinculos de un telefono siguiendo el orden de ADR-05.

    Args:
        telefono_e164: Telefono del apoderado, ya normalizado a E.164 por
            `apps.common.phone.normalizar_e164`.

    Returns:
        Los vinculos activos del telefono. Lista vacia significa "ese telefono
        no tiene estudiantes y eso se pudo comprobar".

    Raises:
        UpstreamSchoolDbUnavailable: No se hallo nada y ademas hubo colegios que
            fallaron o agotaron el timeout, asi que la respuesta no es fiable.
    """
    if not telefono_e164:
        return []

    # 1. Cache.
    cacheados = cache_directorio.leer_cache(telefono_e164)
    if cacheados is not None:
        logger.debug("directorio_hit_cache", extra={"vinculos": len(cacheados)})
        return [v for v in cacheados if v.activo]

    # 2. Proyeccion de la BD central.
    persistidos = listar_persistidos(telefono_e164)
    if persistidos:
        cache_directorio.escribir_cache(telefono_e164, persistidos)
        logger.debug("directorio_hit_central", extra={"vinculos": len(persistidos)})
        return persistidos

    # Si la central ya conoce el teléfono pero solo tiene vínculos inactivos,
    # no hace falta (ni conviene) fan-out a colegios: la respuesta es "sin vínculo".
    if Directorio.objects.filter(telefono=telefono_e164).exists():
        cache_directorio.escribir_cache(telefono_e164, [])
        logger.debug("directorio_solo_inactivos")
        return []

    # 3. Las BDs de colegio, en paralelo.
    resultado = resolver_en_colegios(telefono_e164)
    activos = [v for v in resultado.vinculos if v.activo]

    if activos:
        # 4. Se persiste y se cachea para que el siguiente login no repita la ronda.
        guardar_vinculos(activos)
        cache_directorio.escribir_cache(telefono_e164, activos)
        logger.info(
            "directorio_resuelto_en_colegios",
            extra={
                "vinculos": len(activos),
                "colegios_ok": len(resultado.consultados),
                "colegios_fallidos": len(resultado.fallidos),
            },
        )
        return activos

    # 5. Nada hallado. Solo es un "no existe" si todos los colegios respondieron.
    if not resultado.todos_respondieron:
        logger.warning(
            "directorio_sin_verificar",
            extra={
                "colegios_ok": len(resultado.consultados),
                "colegios_fallidos": len(resultado.fallidos),
            },
        )
        raise UpstreamSchoolDbUnavailable(
            contexto={"colegios_fallidos": resultado.fallidos}
        )

    logger.info("directorio_sin_vinculos", extra={"colegios_ok": len(resultado.consultados)})
    return []


def buscar_por_documento(vinculos: list[VinculoDTO], documento: str) -> VinculoDTO | None:
    """Busca en los vinculos el estudiante cuyo `codigo_barras` coincide.

    La comparacion es exacta salvo por espacios y mayusculas: ADR-07 renuncia al
    OTP y se apoya justo en que esta coincidencia sea estricta.

    Args:
        vinculos: Vinculos ya resueltos del telefono.
        documento: `documento_estudiante` tal como lo envio el cliente.

    Returns:
        El vinculo que coincide, o `None`.
    """
    buscado = (documento or "").strip().upper()
    if not buscado:
        return None
    for vinculo in vinculos:
        if (vinculo.codigo_barras or "").strip().upper() == buscado:
            return vinculo
    return None


def marcar_inactivos_no_vistos(tenant_id: str, desde) -> list[str]:
    """Da de baja los vinculos de un colegio que la reconciliacion no volvio a ver.

    Args:
        tenant_id: Colegio reconciliado.
        desde: Marca de tiempo del inicio de la pasada. Todo vinculo de ese
            colegio con `sincronizado_en` anterior ya no existe en el origen.

    Returns:
        Los telefonos afectados, para invalidar su cache.
    """
    obsoletos = Directorio.objects.filter(tenant_id=tenant_id, estado_vinculo=VINCULO_ACTIVO).exclude(
        sincronizado_en__gte=desde
    )
    telefonos = list(obsoletos.values_list("telefono", flat=True).distinct())
    obsoletos.update(estado_vinculo=VINCULO_INACTIVO, sincronizado_en=timezone.now())
    return telefonos
