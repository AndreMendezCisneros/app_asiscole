"""Pruebas de bandeja e idempotencia de mensajes."""

from __future__ import annotations

from datetime import datetime, timezone as dt_timezone

import pytest
from django.utils import timezone

from apps.cuentas.models import Apoderado
from apps.mensajeria.models import Mensaje
from apps.mensajeria.services import _emitido_iso, listar_mensajes, marcar_leidos


def test_emitido_iso_corrige_utc_etiquetado_como_lima():
    """Postgres timestamp naive UTC leido como America/Lima (+5 h en API)."""
    lima = timezone.get_current_timezone()
    # Simula lectura Django: reloj 19:17 UTC guardado como aware Lima 19:17.
    mal = timezone.make_aware(
        datetime(2026, 7, 27, 19, 17, 44, 190001),
        lima,
    )
    assert _emitido_iso(mal) == "2026-07-27T19:17:44.190001Z"


def test_emitido_iso_naive_utc():
    naive = datetime(2026, 7, 27, 19, 17, 44, 190001)
    assert _emitido_iso(naive) == "2026-07-27T19:17:44.190001Z"


def test_emitido_iso_utc_consciente():
    utc = datetime(2026, 7, 27, 19, 17, 44, 190001, tzinfo=dt_timezone.utc)
    assert _emitido_iso(utc) == "2026-07-27T19:17:44.190001Z"


@pytest.mark.django_db
def test_listar_mensajes_solo_del_apoderado():
    a1 = Apoderado.objects.create(telefono="+51911111111")
    a2 = Apoderado.objects.create(telefono="+51922222222")
    Mensaje.objects.create(
        apoderado=a1,
        tenant_id="jean_piaget",
        tipo="entrada",
        texto="Hola A",
        origen_evento="entrada:1",
    )
    Mensaje.objects.create(
        apoderado=a2,
        tenant_id="jean_piaget",
        tipo="entrada",
        texto="Hola B",
        origen_evento="entrada:1",
    )
    bandeja = listar_mensajes(a1)
    assert len(bandeja["items"]) == 1
    assert bandeja["items"][0]["texto"] == "Hola A"


@pytest.mark.django_db
def test_marcar_leidos_no_toca_ajenos():
    a1 = Apoderado.objects.create(telefono="+51911111111")
    a2 = Apoderado.objects.create(telefono="+51922222222")
    m1 = Mensaje.objects.create(
        apoderado=a1, tenant_id="t", tipo="aviso", texto="uno"
    )
    m2 = Mensaje.objects.create(
        apoderado=a2, tenant_id="t", tipo="aviso", texto="dos"
    )
    marcar_leidos(a1, [str(m1.pk), str(m2.pk)])
    m1.refresh_from_db()
    m2.refresh_from_db()
    assert m1.leido is True
    assert m2.leido is False


@pytest.mark.django_db
def test_idempotencia_origen_por_apoderado():
    a = Apoderado.objects.create(telefono="+51933333333")
    Mensaje.objects.create(
        apoderado=a,
        tenant_id="t",
        tipo="entrada",
        texto="x",
        origen_evento="entrada:99",
    )
    with pytest.raises(Exception):
        Mensaje.objects.create(
            apoderado=a,
            tenant_id="t",
            tipo="entrada",
            texto="y",
            origen_evento="entrada:99",
        )
