"""Ingesta y serialización de notas semanales (`asis_nota`).

El contrato canónico es `tipo: nota`. El SIE de Academy todavía puede mandar
`tipo: aviso` con `payload.contexto=nota` y alias (`semana`, `area`): el canal
lo normaliza aquí. No se crea `asis_mensaje`.
"""

from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any

from django.db import IntegrityError, transaction
from django.utils.dateparse import parse_date, parse_datetime

from apps.common.errors import ValidationError
from apps.mensajeria.models import NotaSemanal

_RE_NOTA_SOBRE = re.compile(r"(\d+(?:[.,]\d+)?)\s*/\s*(\d+)")
_RE_SEMANA = re.compile(r"\(([^)]*semana[^)]*)\)", re.IGNORECASE)
_RE_PAREN = re.compile(r"\(([^)]{1,64})\)")
_RE_CARRERA = re.compile(r"Carrera:\s*(.+?)(?:\.|$)", re.IGNORECASE)
_RE_AREA = re.compile(r"(?:Área|Area):\s*(.+?)(?:\.|$)", re.IGNORECASE)
_RE_ANIO_SEMANA = re.compile(r"^(\d{4})-(\d{1,2})$")

_CAMPOS_RELLENABLES = (
    "semana_codigo",
    "semana_etiqueta",
    "fecha_inicio",
    "fecha_fin",
    "nota_maxima",
    "area_codigo",
    "area_nombre",
    "carrera",
    "registrado_en",
)

_MAX_NOTA = 32
_MAX_SEMANA = 64
_MAX_AREA = 160
_MAX_CARRERA = 160


def _texto(valor: Any, tope: int) -> str | None:
    if valor is None:
        return None
    limpio = " ".join(str(valor).split())
    if not limpio:
        return None
    return limpio[:tope]


def _fecha(valor: Any) -> date | None:
    if valor is None or valor == "":
        return None
    if isinstance(valor, datetime):
        return valor.date()
    if isinstance(valor, date):
        return valor
    parsed = parse_date(str(valor).strip()[:10])
    return parsed


def _momento(valor: Any) -> datetime | None:
    if valor is None or valor == "":
        return None
    if isinstance(valor, datetime):
        return valor
    return parse_datetime(str(valor).strip())


def _nota_desde_texto(texto: Any, maxima_previa: str | None) -> tuple[str | None, str | None]:
    """Saca `18.5/20` del texto libre. No registra el contenido."""
    hallado = _RE_NOTA_SOBRE.search(str(texto or ""))
    if not hallado:
        return None, maxima_previa
    valor = hallado.group(1).replace(",", ".")
    tope = _texto(hallado.group(2), _MAX_NOTA)
    return _texto(valor, _MAX_NOTA), maxima_previa or tope


def _semana_desde_texto(texto: Any) -> str | None:
    crudo = str(texto or "")
    hallado = _RE_SEMANA.search(crudo)
    if hallado:
        return _texto(hallado.group(1), _MAX_SEMANA)
    paren = _RE_PAREN.search(crudo)
    if paren:
        return _texto(paren.group(1), _MAX_SEMANA)
    return None


def _dato_etiquetado(patron: re.Pattern[str], texto: Any, tope: int) -> str | None:
    hallado = patron.search(str(texto or ""))
    if not hallado:
        return None
    return _texto(hallado.group(1), tope)


def _etiqueta_legible(codigo: str | None, etiqueta: str | None) -> str | None:
    """`2026-02` se muestra como `Semana 2`. No inventa fechas."""
    crudo = (etiqueta or codigo or "").strip()
    if not crudo:
        return etiqueta or codigo
    hallado = _RE_ANIO_SEMANA.match(crudo)
    if hallado:
        return f"Semana {int(hallado.group(2))}"
    return crudo


def upsert_nota(
    *,
    tenant_id: str,
    id_estudiante: int,
    id_registro: int,
    payload: dict[str, Any],
) -> tuple[NotaSemanal, bool]:
    """Inserta o reutiliza la nota. No pisa una fila ya existente.

    Returns:
        `(fila, created)`. `created=False` si el SIE reintenta el mismo
        `id_registro`.

    Raises:
        ValidationError: Falta la nota o el identificador de semana.
    """
    datos = dict(payload or {})
    nota = _texto(datos.get("nota"), _MAX_NOTA)
    nota_maxima = _texto(datos.get("nota_maxima"), _MAX_NOTA)
    if not nota:
        nota, nota_maxima = _nota_desde_texto(datos.get("texto_libre"), nota_maxima)
    semana_codigo = _texto(
        datos.get("semana_codigo") or datos.get("semana"), _MAX_SEMANA
    )
    semana_etiqueta = _texto(
        datos.get("semana_etiqueta") or datos.get("semana") or semana_codigo,
        _MAX_SEMANA,
    )
    if not semana_codigo and not semana_etiqueta:
        semana_etiqueta = _semana_desde_texto(datos.get("texto_libre")) or "Nota semanal"
        semana_codigo = semana_etiqueta
    if not nota or (not semana_codigo and not semana_etiqueta):
        raise ValidationError("El payload de la nota está incompleto o es inválido.")

    texto_libre = datos.get("texto_libre")
    semana_etiqueta = _etiqueta_legible(semana_codigo, semana_etiqueta)
    campos = {
        "semana_codigo": semana_codigo,
        "semana_etiqueta": semana_etiqueta,
        "fecha_inicio": _fecha(datos.get("fecha_inicio")),
        "fecha_fin": _fecha(datos.get("fecha_fin")),
        "nota": nota,
        "nota_maxima": nota_maxima or "20",
        "area_codigo": _texto(datos.get("area_codigo"), _MAX_AREA),
        "area_nombre": _texto(
            datos.get("area_nombre") or datos.get("area"), _MAX_AREA
        )
        or _dato_etiquetado(_RE_AREA, texto_libre, _MAX_AREA),
        "carrera": _texto(
            datos.get("carrera") or datos.get("carreraNombre"), _MAX_CARRERA
        )
        or _dato_etiquetado(_RE_CARRERA, texto_libre, _MAX_CARRERA),
        "registrado_en": _momento(datos.get("registrado_en")),
    }

    try:
        with transaction.atomic():
            fila = NotaSemanal.objects.create(
                tenant_id=tenant_id,
                id_estudiante=id_estudiante,
                id_registro=id_registro,
                **campos,
            )
        return fila, True
    except IntegrityError:
        existente = NotaSemanal.objects.get(
            tenant_id=tenant_id,
            id_estudiante=id_estudiante,
            id_registro=id_registro,
        )
        _rellenar_vacios(existente, campos)
        return existente, False


def _rellenar_vacios(fila: NotaSemanal, campos: dict[str, Any]) -> None:
    """Completa huecos de una nota ya guardada. No pisa valores existentes."""
    sucios: list[str] = []
    for nombre in _CAMPOS_RELLENABLES:
        nuevo = campos.get(nombre)
        if nuevo in (None, ""):
            continue
        actual = getattr(fila, nombre)
        if actual in (None, ""):
            setattr(fila, nombre, nuevo)
            sucios.append(nombre)
    if sucios:
        fila.save(update_fields=sucios)


def migrar_avisos_contexto_nota() -> int:
    """Pasa avisos ya emitidos con `contexto=nota` a `asis_nota`. Idempotente.

    No escribe el texto ni nombres en logs. Devuelve cuántas filas nuevas creó.
    """
    from apps.mensajeria.models import Mensaje

    creados = 0
    for mensaje in Mensaje.objects.filter(tipo="aviso").iterator():
        meta = mensaje.metadata or {}
        if str(meta.get("contexto") or "").strip().lower() != "nota":
            continue
        origen = mensaje.origen_evento or ""
        try:
            id_registro = int(str(origen).rsplit(":", 1)[-1])
        except (TypeError, ValueError):
            continue
        if id_registro <= 0 or not mensaje.id_estudiante:
            continue
        payload = dict(meta)
        payload.setdefault("texto_libre", mensaje.texto)
        try:
            _fila, created = upsert_nota(
                tenant_id=mensaje.tenant_id,
                id_estudiante=int(mensaje.id_estudiante),
                id_registro=id_registro,
                payload=payload,
            )
        except ValidationError:
            continue
        if created:
            creados += 1
    return creados


def serializar_nota(fila: NotaSemanal) -> dict[str, Any]:
    """Contrato `NotaSemanal` de OpenAPI. Sin nombre del estudiante."""
    momento = fila.registrado_en or fila.emitido_en
    return {
        "id": str(fila.pk),
        "id_registro": fila.id_registro,
        "semana_codigo": fila.semana_codigo,
        "semana_etiqueta": _etiqueta_legible(
            fila.semana_codigo, fila.semana_etiqueta
        ),
        "fecha_inicio": fila.fecha_inicio.isoformat() if fila.fecha_inicio else None,
        "fecha_fin": fila.fecha_fin.isoformat() if fila.fecha_fin else None,
        "nota": fila.nota,
        "nota_maxima": fila.nota_maxima,
        "area_codigo": fila.area_codigo,
        "area_nombre": fila.area_nombre,
        "carrera": fila.carrera,
        "registrado_en": momento.isoformat() if momento else None,
    }
