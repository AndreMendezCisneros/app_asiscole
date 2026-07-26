"""Tareas de Celery del directorio telefonico.

Dos trabajos:

* `reconciliar_directorio`: pasada nocturna que corrige las derivas entre
  `asis_directorio` y la fuente de verdad de cada colegio (ADR-05).
* `precalentar_directorio`: carga la cache antes de la jornada escolar, para que
  el pico de logins de la manana no vaya todo a la BD.

Los resumenes que se registran son solo contadores: ni un telefono, ni un
nombre, ni un `codigo_barras` (Ley N.o 29733).
"""

from __future__ import annotations

import logging
from collections import defaultdict

from celery import shared_task
from django.utils import timezone

from apps.directorio import cache as cache_directorio
from apps.directorio import circuit_breaker, repositorio, services
from apps.directorio.dto import VinculoDTO
from apps.directorio.models import VINCULO_ACTIVO, Directorio

logger = logging.getLogger("asiscole.directorio.tareas")

#: Cuantos vinculos se agrupan antes de escribirlos en la BD central.
TAMANO_LOTE_UPSERT = 500


def _reconciliar_colegio(tenant_id: str) -> dict[str, int]:
    """Reconcilia un colegio y devuelve sus contadores.

    Raises:
        Exception: Cualquier fallo de la BD del colegio se propaga para que el
            llamador lo cuente como colegio no reconciliado.
    """
    inicio = timezone.now()
    lote: list[VinculoDTO] = []
    telefonos_tocados: set[str] = set()
    upserts = 0

    for vinculo in repositorio.iterar_directorio(tenant_id):
        lote.append(vinculo)
        telefonos_tocados.add(vinculo.telefono)
        if len(lote) >= TAMANO_LOTE_UPSERT:
            upserts += services.guardar_vinculos(lote)
            lote = []

    if lote:
        upserts += services.guardar_vinculos(lote)

    dados_de_baja = services.marcar_inactivos_no_vistos(tenant_id, inicio)
    telefonos_tocados.update(dados_de_baja)

    invalidadas = cache_directorio.invalidar_muchos(telefonos_tocados)

    return {
        "upserts": upserts,
        "bajas": len(dados_de_baja),
        "claves_invalidadas": invalidadas,
    }


@shared_task(name="apps.directorio.tasks.reconciliar_directorio", ignore_result=True)
def reconciliar_directorio() -> dict:
    """Reconcilia `asis_directorio` con todas las BDs de colegio.

    Recorre `asis_v_directorio_origen` de cada colegio, hace upsert de lo que
    encuentra, marca como inactivos los vinculos que ya no existen en el origen
    e invalida en Redis las claves de los telefonos afectados.

    Returns:
        Resumen con contadores por colegio y totales.
    """
    resumen: dict[str, object] = {
        "colegios": 0,
        "colegios_fallidos": 0,
        "upserts": 0,
        "bajas": 0,
        "claves_invalidadas": 0,
    }
    detalle: dict[str, dict[str, int]] = {}

    for tenant_id in services.tenants_configurados():
        try:
            contadores = _reconciliar_colegio(tenant_id)
        except Exception:  # noqa: BLE001 — un colegio caido no aborta la pasada
            circuit_breaker.registrar_fallo(tenant_id)
            resumen["colegios_fallidos"] = int(resumen["colegios_fallidos"]) + 1
            logger.warning("reconciliacion_colegio_error", extra={"tenant": tenant_id})
            continue

        circuit_breaker.registrar_exito(tenant_id)
        detalle[tenant_id] = contadores
        resumen["colegios"] = int(resumen["colegios"]) + 1
        for clave in ("upserts", "bajas", "claves_invalidadas"):
            resumen[clave] = int(resumen[clave]) + contadores[clave]

    logger.info("reconciliacion_directorio", extra={**resumen, "detalle": detalle})
    return resumen


@shared_task(name="apps.directorio.tasks.precalentar_directorio", ignore_result=True)
def precalentar_directorio() -> dict:
    """Carga en Redis los telefonos activos del directorio.

    Pensado para ejecutarse justo antes del inicio de la jornada escolar, que es
    cuando se concentran los logins y las entradas.

    Returns:
        Resumen con cuantos telefonos y vinculos se cargaron.
    """
    agrupados: dict[str, list[VinculoDTO]] = defaultdict(list)

    consulta = Directorio.objects.filter(estado_vinculo=VINCULO_ACTIVO).order_by("telefono", "id")
    for fila in consulta.iterator(chunk_size=1000):
        agrupados[fila.telefono].append(VinculoDTO.desde_modelo(fila))

    for telefono, vinculos in agrupados.items():
        cache_directorio.escribir_cache(telefono, vinculos)

    resumen = {"telefonos": len(agrupados), "vinculos": sum(len(v) for v in agrupados.values())}
    logger.info("precalentado_directorio", extra=resumen)
    return resumen
