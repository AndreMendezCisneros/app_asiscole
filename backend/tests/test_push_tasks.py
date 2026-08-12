"""Pruebas de envío push con transporte mock (sin FCM real)."""

from __future__ import annotations

from dataclasses import dataclass

import pytest

from apps.cuentas.models import Apoderado, PushToken
from apps.mensajeria.models import TIPO_ENTRADA, Mensaje
from apps.mensajeria.tasks import enviar_push_mensaje, reintentar_push_pendientes


@dataclass
class _ResultadoFake:
    hubo_entrega: bool = True


class _PushFake:
    def __init__(self):
        self.llamadas = 0

    def enviar(self, tokens, carga):
        self.llamadas += 1
        return _ResultadoFake(hubo_entrega=True)


@pytest.mark.django_db
def test_enviar_push_mensaje_marca_entregado(monkeypatch):
    apo = Apoderado.objects.create(telefono="+51988880001")
    PushToken.objects.create(
        apoderado=apo,
        device_id="dev-1",
        token="fake-fcm-token",
        plataforma="android",
        activo=True,
    )
    mensaje = Mensaje.objects.create(
        apoderado=apo,
        tenant_id="jean_piaget",
        tipo=TIPO_ENTRADA,
        texto="Entrada registrada",
        entregado=False,
    )
    fake = _PushFake()
    monkeypatch.setattr(
        "apps.mensajeria.tasks.ServicioPush",
        lambda: fake,
    )

    assert enviar_push_mensaje(str(mensaje.pk)) is True
    mensaje.refresh_from_db()
    assert mensaje.entregado is True
    assert fake.llamadas == 1


@pytest.mark.django_db
def test_reintentar_push_pendientes(monkeypatch):
    apo = Apoderado.objects.create(telefono="+51988880002")
    PushToken.objects.create(
        apoderado=apo,
        device_id="dev-2",
        token="fake-fcm-token-2",
        plataforma="android",
        activo=True,
    )
    Mensaje.objects.create(
        apoderado=apo,
        tenant_id="jean_piaget",
        tipo=TIPO_ENTRADA,
        texto="Pendiente",
        entregado=False,
    )
    fake = _PushFake()
    monkeypatch.setattr(
        "apps.mensajeria.tasks.ServicioPush",
        lambda: fake,
    )

    enviados = reintentar_push_pendientes(apo)
    assert enviados == 1
    assert fake.llamadas == 1
