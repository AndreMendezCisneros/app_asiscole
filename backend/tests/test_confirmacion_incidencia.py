"""Pruebas de confirmación de incidencias (BD central)."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from django.utils import timezone

from apps.academico import services
from apps.common.errors import StudentLinkNotFound
from apps.cuentas.models import Apoderado, ConfirmacionIncidencia
from apps.directorio.models import VINCULO_ACTIVO, Directorio

TENANT = "jean_piaget"
ESTUDIANTE_ID = 101


@pytest.fixture
def apoderado_con_vinculo(db):
    apo = Apoderado.objects.create(telefono="+51944440001")
    Directorio.objects.create(
        telefono=apo.telefono,
        tenant_id=TENANT,
        id_estudiante=ESTUDIANTE_ID,
        codigo_barras="70000001",
        nombre_estudiante="Hijo",
        estado_vinculo=VINCULO_ACTIVO,
    )
    return apo


@pytest.mark.django_db
def test_confirmar_incidencia_crea_fila_central(apoderado_con_vinculo):
    apo = apoderado_con_vinculo
    with (
        patch("apps.academico.services.circuit_breaker") as cb,
        patch("apps.academico.services.Incidencia") as IncidenciaMock,
    ):
        cb.permite_intentar.return_value = True
        qs = MagicMock()
        qs.filter.return_value = qs
        qs.exclude.return_value = qs
        qs.exists.return_value = True
        IncidenciaMock.objects.using.return_value = qs

        services.confirmar_incidencia(
            apo, incidencia_id=55, estudiante_id=ESTUDIANTE_ID
        )

    fila = ConfirmacionIncidencia.objects.get()
    assert fila.apoderado_id == apo.pk
    assert fila.tenant_id == TENANT
    assert fila.id_incidencia_colegio == 55
    assert fila.confirmada_en is not None


@pytest.mark.django_db
def test_confirmar_incidencia_es_idempotente(apoderado_con_vinculo):
    apo = apoderado_con_vinculo
    ConfirmacionIncidencia.objects.create(
        apoderado=apo,
        tenant_id=TENANT,
        id_incidencia_colegio=55,
        confirmada_en=timezone.now(),
    )
    with (
        patch("apps.academico.services.circuit_breaker") as cb,
        patch("apps.academico.services.Incidencia") as IncidenciaMock,
    ):
        cb.permite_intentar.return_value = True
        qs = MagicMock()
        qs.filter.return_value = qs
        qs.exclude.return_value = qs
        qs.exists.return_value = True
        IncidenciaMock.objects.using.return_value = qs

        services.confirmar_incidencia(
            apo, incidencia_id=55, estudiante_id=ESTUDIANTE_ID
        )

    assert ConfirmacionIncidencia.objects.count() == 1


@pytest.mark.django_db
def test_confirmar_incidencia_inexistente_404(apoderado_con_vinculo):
    apo = apoderado_con_vinculo
    with (
        patch("apps.academico.services.circuit_breaker") as cb,
        patch("apps.academico.services.Incidencia") as IncidenciaMock,
    ):
        cb.permite_intentar.return_value = True
        qs = MagicMock()
        qs.filter.return_value = qs
        qs.exclude.return_value = qs
        qs.exists.return_value = False
        IncidenciaMock.objects.using.return_value = qs

        with pytest.raises(StudentLinkNotFound):
            services.confirmar_incidencia(
                apo, incidencia_id=99, estudiante_id=ESTUDIANTE_ID
            )


@pytest.mark.django_db
def test_flags_confirmacion_en_mapa(apoderado_con_vinculo):
    apo = apoderado_con_vinculo
    ConfirmacionIncidencia.objects.create(
        apoderado=apo,
        tenant_id=TENANT,
        id_incidencia_colegio=7,
        confirmada_en=timezone.now(),
    )
    mapa = services._mapa_confirmaciones(apo, tenant_id=TENANT, ids=[7, 8])
    assert 7 in mapa
    assert 8 not in mapa
    flags = services._flags_confirmacion(mapa[7])
    assert flags["confirmada"] is True
    assert flags["confirmada_en"] is not None
    assert services._flags_confirmacion(None) == {
        "confirmada": False,
        "confirmada_en": None,
    }


@pytest.mark.django_db
def test_listar_incidencias_mezcla_confirmacion(apoderado_con_vinculo):
    apo = apoderado_con_vinculo
    ConfirmacionIncidencia.objects.create(
        apoderado=apo,
        tenant_id=TENANT,
        id_incidencia_colegio=1,
        confirmada_en=timezone.now(),
    )
    incidencia = SimpleNamespace(
        pk=1,
        fecha_hora_registro=timezone.now(),
        falta=SimpleNamespace(categoria="Leve", nombre_falta="Tardanza", es_grave=False),
        estado_evidencia="Sin evidencia",
        usuario_registro=SimpleNamespace(nombre_completo="Tutor"),
    )

    class _QS(list):
        def select_related(self, *args):
            return self

        def filter(self, **kwargs):
            return self

        def exclude(self, **kwargs):
            return self

        def order_by(self, *args):
            return self

    with (
        patch("apps.academico.services.circuit_breaker") as cb,
        patch("apps.academico.services.Incidencia") as IncidenciaMock,
    ):
        cb.permite_intentar.return_value = True
        IncidenciaMock.objects.using.return_value = _QS([incidencia])

        resultado = services.listar_incidencias(apo, estudiante_id=ESTUDIANTE_ID)

    item = resultado["items"][0]
    assert item["confirmada"] is True
    assert item["confirmada_en"] is not None
