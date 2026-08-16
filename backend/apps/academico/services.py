"""Consultas de asistencia, incidencias y notas.

Asistencias e incidencias se leen de la BD del colegio (solo lectura).
Las confirmaciones de incidencia viven en la BD central
(`asis_confirmacion_incidencia`) y se fusionan al listar/detallar.
Las notas semanales viven en la BD central (`asis_nota`) porque el SIE las
empuja por ingesta; no se consultan en vivo al colegio.
"""

from __future__ import annotations

import calendar
from datetime import date

from django.utils import timezone

from apps.academico.authz import vinculo_estudiante
from apps.academico.models import EvidenciaFotografica, Incidencia, RegistroLlegada
from apps.common.errors import StudentLinkNotFound, UpstreamSchoolDbUnavailable
from apps.cuentas.models import Apoderado, ConfirmacionIncidencia
from apps.directorio import circuit_breaker
from config.db_router import tenant_alias


def _hoy_lima() -> date:
    return timezone.localdate()


def _mapear_estado(estado_colegio: str) -> str:
    valor = (estado_colegio or "").strip().lower()
    if valor == "a tiempo":
        return "a_tiempo"
    if valor == "tarde":
        return "tarde"
    return "sin_registro"


def _mapa_confirmaciones(
    apoderado: Apoderado, *, tenant_id: str, ids: list[int]
) -> dict[int, ConfirmacionIncidencia]:
    """Índice id_incidencia_colegio → fila de confirmación en BD central."""
    if not ids:
        return {}
    filas = ConfirmacionIncidencia.objects.filter(
        apoderado=apoderado,
        tenant_id=tenant_id,
        id_incidencia_colegio__in=ids,
    )
    return {f.id_incidencia_colegio: f for f in filas}


def _flags_confirmacion(
    confirmacion: ConfirmacionIncidencia | None,
) -> dict:
    if confirmacion is None:
        return {"confirmada": False, "confirmada_en": None}
    return {
        "confirmada": True,
        "confirmada_en": confirmacion.confirmada_en.isoformat(),
    }


def agenda_mensual(
    apoderado: Apoderado, *, estudiante_id: int, anio: int, mes: int
) -> dict:
    """Agenda del mes con falta/sin_registro derivados (RF-F01, RF-F02)."""
    if mes < 1 or mes > 12:
        from apps.common.errors import ValidationError

        raise ValidationError("El mes debe estar entre 1 y 12.")

    vinculo = vinculo_estudiante(apoderado, estudiante_id)
    if not circuit_breaker.permite_intentar(vinculo.tenant_id):
        raise UpstreamSchoolDbUnavailable()

    alias = tenant_alias(vinculo.tenant_id)
    try:
        registros = {
            r.fecha: r
            for r in RegistroLlegada.objects.using(alias).filter(
                estudiante_id=estudiante_id,
                fecha__year=anio,
                fecha__month=mes,
            )
        }
    except Exception as exc:  # noqa: BLE001
        circuit_breaker.registrar_fallo(vinculo.tenant_id)
        raise UpstreamSchoolDbUnavailable() from exc

    circuit_breaker.registrar_exito(vinculo.tenant_id)
    hoy = _hoy_lima()
    dias_mes = calendar.monthrange(anio, mes)[1]
    items = []
    for dia in range(1, dias_mes + 1):
        fecha = date(anio, mes, dia)
        reg = registros.get(fecha)
        if reg is not None:
            items.append(
                {
                    "fecha": fecha.isoformat(),
                    "estado": _mapear_estado(reg.estado),
                    "hora_entrada": reg.hora_llegada.strftime("%H:%M") if reg.hora_llegada else None,
                    "hora_salida": reg.hora_salida.strftime("%H:%M") if reg.hora_salida else None,
                    "tipo_salida": reg.tipo_salida,
                }
            )
        else:
            items.append(
                {
                    "fecha": fecha.isoformat(),
                    "estado": "falta" if fecha < hoy else "sin_registro",
                    "hora_entrada": None,
                    "hora_salida": None,
                    "tipo_salida": None,
                }
            )
    return {"items": items}


def listar_incidencias(
    apoderado: Apoderado,
    *,
    estudiante_id: int,
    desde: str | None = None,
    hasta: str | None = None,
) -> dict:
    """Listado de incidencias no anuladas del estudiante."""
    vinculo = vinculo_estudiante(apoderado, estudiante_id)
    if not circuit_breaker.permite_intentar(vinculo.tenant_id):
        raise UpstreamSchoolDbUnavailable()
    alias = tenant_alias(vinculo.tenant_id)
    try:
        qs = (
            Incidencia.objects.using(alias)
            .select_related("falta", "usuario_registro")
            .filter(estudiante_id=estudiante_id)
            .exclude(estado="Anulada")
            .order_by("-fecha_hora_registro")
        )
        if desde:
            qs = qs.filter(fecha_hora_registro__date__gte=desde)
        if hasta:
            qs = qs.filter(fecha_hora_registro__date__lte=hasta)
        filas = list(qs[:200])
        ids = [i.pk for i in filas]
        confirmaciones = _mapa_confirmaciones(
            apoderado, tenant_id=vinculo.tenant_id, ids=ids
        )
        items = [
            {
                "id": i.pk,
                "fecha": i.fecha_hora_registro.isoformat(),
                "categoria": i.falta.categoria,
                "falta": i.falta.nombre_falta,
                "es_grave": i.falta.es_grave,
                "tiene_evidencia": i.estado_evidencia == "Con evidencia",
                "reportado_por": i.usuario_registro.nombre_completo,
                **_flags_confirmacion(confirmaciones.get(i.pk)),
            }
            for i in filas
        ]
    except Exception as exc:  # noqa: BLE001
        circuit_breaker.registrar_fallo(vinculo.tenant_id)
        raise UpstreamSchoolDbUnavailable() from exc
    circuit_breaker.registrar_exito(vinculo.tenant_id)
    return {"items": items}


def detalle_incidencia(
    apoderado: Apoderado, *, incidencia_id: int, estudiante_id: int
) -> dict:
    """Detalle con evidencias (RF-G01, RF-G04)."""
    vinculo = vinculo_estudiante(apoderado, estudiante_id)
    if not circuit_breaker.permite_intentar(vinculo.tenant_id):
        raise UpstreamSchoolDbUnavailable()
    alias = tenant_alias(vinculo.tenant_id)
    try:
        incidencia = (
            Incidencia.objects.using(alias)
            .select_related("falta", "usuario_registro")
            .filter(pk=incidencia_id, estudiante_id=estudiante_id)
            .exclude(estado="Anulada")
            .first()
        )
        if incidencia is None:
            raise StudentLinkNotFound()
        evidencias = [
            {"url": e.ruta_archivo, "tipo_mime": e.tipo_mime}
            for e in EvidenciaFotografica.objects.using(alias).filter(incidencia=incidencia)
        ]
    except StudentLinkNotFound:
        raise
    except Exception as exc:  # noqa: BLE001
        circuit_breaker.registrar_fallo(vinculo.tenant_id)
        raise UpstreamSchoolDbUnavailable() from exc
    circuit_breaker.registrar_exito(vinculo.tenant_id)

    confirmacion = ConfirmacionIncidencia.objects.filter(
        apoderado=apoderado,
        tenant_id=vinculo.tenant_id,
        id_incidencia_colegio=incidencia.pk,
    ).first()
    return {
        "id": incidencia.pk,
        "fecha": incidencia.fecha_hora_registro.isoformat(),
        "categoria": incidencia.falta.categoria,
        "falta": incidencia.falta.nombre_falta,
        "es_grave": incidencia.falta.es_grave,
        "tiene_evidencia": incidencia.estado_evidencia == "Con evidencia",
        "reportado_por": incidencia.usuario_registro.nombre_completo,
        "observaciones": incidencia.observaciones,
        "evidencias": evidencias,
        **_flags_confirmacion(confirmacion),
    }


def confirmar_incidencia(
    apoderado: Apoderado, *, incidencia_id: int, estudiante_id: int
) -> None:
    """Marca la incidencia como confirmada en la BD central (idempotente).

    Verifica que la incidencia exista y pertenezca al estudiante vinculado;
    no escribe en la BD del colegio.
    """
    vinculo = vinculo_estudiante(apoderado, estudiante_id)
    if not circuit_breaker.permite_intentar(vinculo.tenant_id):
        raise UpstreamSchoolDbUnavailable()
    alias = tenant_alias(vinculo.tenant_id)
    try:
        existe = (
            Incidencia.objects.using(alias)
            .filter(pk=incidencia_id, estudiante_id=estudiante_id)
            .exclude(estado="Anulada")
            .exists()
        )
    except Exception as exc:  # noqa: BLE001
        circuit_breaker.registrar_fallo(vinculo.tenant_id)
        raise UpstreamSchoolDbUnavailable() from exc
    circuit_breaker.registrar_exito(vinculo.tenant_id)

    if not existe:
        raise StudentLinkNotFound()

    ConfirmacionIncidencia.objects.get_or_create(
        apoderado=apoderado,
        tenant_id=vinculo.tenant_id,
        id_incidencia_colegio=incidencia_id,
        defaults={"confirmada_en": timezone.now()},
    )


def listar_notas(apoderado: Apoderado, *, estudiante_id: int) -> dict:
    """Notas ingeridas del estudiante en el colegio del vínculo activo.

    No consulta la BD del colegio: las filas salen de `asis_nota`.
    """
    from apps.mensajeria.models import NotaSemanal
    from apps.mensajeria.notas import serializar_nota

    vinculo = vinculo_estudiante(apoderado, estudiante_id)
    filas = NotaSemanal.objects.filter(
        tenant_id=vinculo.tenant_id,
        id_estudiante=estudiante_id,
    ).order_by("-fecha_inicio", "-semana_codigo", "-emitido_en")
    return {"items": [serializar_nota(f) for f in filas]}
