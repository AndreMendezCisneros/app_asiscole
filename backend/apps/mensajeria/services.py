"""Servicios de la bandeja de mensajes del apoderado."""

from __future__ import annotations

import base64
from datetime import datetime

from django.db.models import Count, Q, QuerySet
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from apps.common.errors import ValidationError
from apps.cuentas.models import Apoderado
from apps.mensajeria.models import Mensaje


def _decodificar_cursor(cursor: str | None) -> datetime | None:
    if not cursor:
        return None
    try:
        crudo = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        momento = parse_datetime(crudo)
        if momento is None:
            raise ValueError
        if timezone.is_naive(momento):
            momento = timezone.make_aware(momento, timezone.get_current_timezone())
        return momento
    except (ValueError, TypeError, UnicodeError):
        raise ValidationError("El cursor de paginación no es válido.") from None


def _codificar_cursor(momento: datetime) -> str:
    return base64.urlsafe_b64encode(momento.isoformat().encode("utf-8")).decode("ascii")


def _serializar(mensaje: Mensaje) -> dict:
    meta = mensaje.metadata or {}
    return {
        "id": str(mensaje.pk),
        "tipo": mensaje.tipo,
        "texto": mensaje.texto,
        "colegio": mensaje.tenant_id,
        "estudiante_id": mensaje.id_estudiante,
        "estudiante_nombre": meta.get("estudiante_nombre"),
        "emitido_en": mensaje.emitido_en.isoformat(),
        "entregado": mensaje.entregado,
        "leido": mensaje.leido,
        "metadata": meta,
    }


def listar_mensajes(
    apoderado: Apoderado,
    *,
    since: str | None = None,
    cursor: str | None = None,
    limit: int = 50,
    tipo: str | None = None,
) -> dict:
    """Bandeja incremental del apoderado (RF-D01, RF-D06)."""
    limite = max(1, min(int(limit or 50), 200))
    qs: QuerySet[Mensaje] = Mensaje.objects.filter(apoderado=apoderado)

    if tipo:
        qs = qs.filter(tipo=tipo)

    if since:
        momento = parse_datetime(since)
        if momento is None:
            raise ValidationError("El parámetro since no es una fecha válida.")
        if timezone.is_naive(momento):
            momento = timezone.make_aware(momento, timezone.get_current_timezone())
        # Workaround: con TIME_ZONE=America/Lima + pooler Supabase, los
        # timestamptz a veces quedan con el reloj local guardado como UTC.
        # Si el cliente manda el isoformat del API (con offset -05) y Django lo
        # interpreta a UTC absoluto, `emitido_en__gt` oculta mensajes posteriores.
        # Comparar el reloj civil del `since` como UTC alinea el filtro con esos
        # valores. Cuando la BD guarde instantes correctos, el cliente ya no
        # depende de `since` (trae la bandeja completa reciente).
        from datetime import timezone as dt_tz

        momento_filtro = momento.replace(tzinfo=dt_tz.utc)
        qs = qs.filter(emitido_en__gt=momento_filtro)

    cursor_dt = _decodificar_cursor(cursor)
    if cursor_dt is not None:
        qs = qs.filter(emitido_en__lt=cursor_dt)

    filas = list(qs.order_by("-emitido_en")[: limite + 1])
    hay_mas = len(filas) > limite
    pagina = filas[:limite]
    next_cursor = _codificar_cursor(pagina[-1].emitido_en) if hay_mas and pagina else None

    badges = (
        Mensaje.objects.filter(apoderado=apoderado, leido=False)
        .values("tipo")
        .annotate(total=Count("id"))
    )
    no_leidos = {fila["tipo"]: fila["total"] for fila in badges}

    return {
        "items": [_serializar(m) for m in pagina],
        "next_cursor": next_cursor,
        "no_leidos_por_canal": no_leidos,
    }


def marcar_leidos(apoderado: Apoderado, ids: list[str]) -> int:
    """Marca como leídos solo los mensajes del apoderado autenticado."""
    if not ids:
        raise ValidationError("Debes indicar al menos un mensaje.")
    ahora = timezone.now()
    return Mensaje.objects.filter(apoderado=apoderado, id__in=ids).filter(
        Q(leido=False) | Q(leido=True)
    ).update(leido=True, leido_en=ahora)
