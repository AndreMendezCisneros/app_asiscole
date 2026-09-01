"""Propaga lectura/confirmación de incidencia al colegio (SIE web).

Dos señales de la app:

* `POST /mensajes/leidos` (check azul en la bandeja) → `revisado_app`
* `POST /incidencias/{id}/confirmar` (página Incidencias) → `confirmada_app`
  y también `revisado_app`
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import Any

logger = logging.getLogger("asiscole.mensajeria.revisado")

_SQL_MARCAR_REVISADO = """
    UPDATE public.incidencias
       SET revisado_app = TRUE,
           revisado_app_en = COALESCE(revisado_app_en, now())
     WHERE id_incidencia = ANY(%s)
       AND COALESCE(revisado_app, FALSE) = FALSE
"""

_SQL_MARCAR_CONFIRMADA = """
    UPDATE public.incidencias
       SET revisado_app = TRUE,
           revisado_app_en = COALESCE(revisado_app_en, now()),
           confirmada_app = TRUE,
           confirmada_app_en = COALESCE(confirmada_app_en, now())
     WHERE id_incidencia = ANY(%s)
"""


def id_incidencia_desde_mensaje(
    *,
    tipo: str | None,
    origen_evento: str | None,
    metadata: dict[str, Any] | None = None,
) -> int | None:
    """Extrae el id de incidencia del colegio a partir del mensaje del canal."""
    if (tipo or "").strip().lower() != "incidencia":
        return None

    origen = (origen_evento or "").strip()
    if origen.lower().startswith("incidencia:"):
        sufijo = origen.split(":", 1)[1].strip()
        if sufijo.isdigit():
            return int(sufijo)

    extra = metadata or {}
    crudo = extra.get("id_registro", extra.get("id_incidencia"))
    if crudo is None:
        return None
    try:
        valor = int(crudo)
    except (TypeError, ValueError):
        return None
    return valor if valor > 0 else None


def ids_incidencia_por_tenant(filas: list[dict[str, Any]]) -> dict[str, list[int]]:
    """Agrupa ids de incidencia por tenant, sin duplicados y en orden estable."""
    agrupados: dict[str, list[int]] = defaultdict(list)
    vistos: dict[str, set[int]] = defaultdict(set)
    for fila in filas:
        tenant_id = str(fila.get("tenant_id") or "").strip()
        if not tenant_id:
            continue
        incidencia_id = id_incidencia_desde_mensaje(
            tipo=str(fila.get("tipo") or ""),
            origen_evento=fila.get("origen_evento"),
            metadata=fila.get("metadata") if isinstance(fila.get("metadata"), dict) else None,
        )
        if incidencia_id is None or incidencia_id in vistos[tenant_id]:
            continue
        vistos[tenant_id].add(incidencia_id)
        agrupados[tenant_id].append(incidencia_id)
    return dict(agrupados)


def _ejecutar_por_tenant(sql: str, por_tenant: dict[str, list[int]], log_ok: str, log_fail: str) -> dict[str, int]:
    from django.db import connections

    from config.db_router import tenant_alias

    resumen: dict[str, int] = {}
    for tenant_id, ids in por_tenant.items():
        if not ids:
            continue
        try:
            alias = tenant_alias(tenant_id)
            with connections[alias].cursor() as cursor:
                cursor.execute(sql, [ids])
                resumen[tenant_id] = cursor.rowcount or 0
        except Exception:  # noqa: BLE001
            logger.warning(log_fail, extra={"tenant": tenant_id, "ids": len(ids)})
            resumen[tenant_id] = 0
    if resumen:
        logger.info(log_ok, extra={"detalle": resumen})
    return resumen


def propagar_revisado_incidencias(filas: list[dict[str, Any]]) -> dict[str, int]:
    """Marca incidencias como revisadas (mensaje leído) en cada BD de colegio."""
    return _ejecutar_por_tenant(
        _SQL_MARCAR_REVISADO,
        ids_incidencia_por_tenant(filas),
        "revisado_colegio_ok",
        "revisado_colegio_fallo",
    )


def marcar_confirmada_colegio(tenant_id: str, incidencia_id: int) -> int:
    """Marca una incidencia confirmada en la página Incidencias de la app."""
    tenant = (tenant_id or "").strip()
    if not tenant or incidencia_id <= 0:
        return 0
    return _ejecutar_por_tenant(
        _SQL_MARCAR_CONFIRMADA,
        {tenant: [int(incidencia_id)]},
        "confirmada_colegio_ok",
        "confirmada_colegio_fallo",
    ).get(tenant, 0)


def propagar_confirmaciones_existentes(filas: list[dict[str, Any]]) -> dict[str, int]:
    """Backfill: filas de asis_confirmacion_incidencia → colegio."""
    agrupados: dict[str, list[int]] = defaultdict(list)
    vistos: dict[str, set[int]] = defaultdict(set)
    for fila in filas:
        tenant_id = str(fila.get("tenant_id") or "").strip()
        try:
            incidencia_id = int(fila.get("id_incidencia_colegio") or 0)
        except (TypeError, ValueError):
            continue
        if not tenant_id or incidencia_id <= 0 or incidencia_id in vistos[tenant_id]:
            continue
        vistos[tenant_id].add(incidencia_id)
        agrupados[tenant_id].append(incidencia_id)
    return _ejecutar_por_tenant(
        _SQL_MARCAR_CONFIRMADA,
        dict(agrupados),
        "confirmada_colegio_ok",
        "confirmada_colegio_fallo",
    )
