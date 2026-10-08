"""iOS sale por FCM: misma credencial que Android y bloque APNs en el mensaje."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from apps.mensajeria.push.base import MensajePush, ResultadoEnvio
from apps.mensajeria.push.facade import ServicioPush
from apps.mensajeria.push.fcm import ProveedorFCM

MENSAJE = MensajePush(
    message_id="0b9f6c1e-2a4d-4c55-9b1e-3f2a1d0c9e88",
    tipo="entrada",
    destino="mensajes/0b9f6c1e-2a4d-4c55-9b1e-3f2a1d0c9e88",
)


class _ProveedorEspia:
    def __init__(self):
        self.lotes: list[list[str]] = []

    def enviar(self, tokens, mensaje):
        self.lotes.append(list(tokens))
        return ResultadoEnvio(enviados=len(tokens))


@pytest.fixture(autouse=True)
def _sin_idempotencia(monkeypatch):
    monkeypatch.setattr(ServicioPush, "_reservar", lambda self, message_id: True)


def test_tokens_ios_salen_por_el_proveedor_fcm():
    espia = _ProveedorEspia()
    servicio = ServicioPush(proveedor_android=espia)

    tokens = [
        SimpleNamespace(token="tok-android", plataforma="android"),
        SimpleNamespace(token="tok-ios", plataforma="ios"),
    ]
    resultado = servicio.enviar(tokens, MENSAJE)

    assert servicio.proveedores["ios"] is servicio.proveedores["android"]
    assert sorted(t for lote in espia.lotes for t in lote) == ["tok-android", "tok-ios"]
    assert resultado.enviados == 2


class _Capturador:
    """Sustituye a `firebase_admin.messaging` y guarda lo que se enviaría."""

    def __init__(self):
        self.peticion = None

    @staticmethod
    def _registro(**kwargs):
        return SimpleNamespace(**kwargs)

    def __getattr__(self, nombre):
        if nombre in {
            "MulticastMessage",
            "Notification",
            "AndroidConfig",
            "AndroidNotification",
            "APNSConfig",
            "APNSPayload",
            "Aps",
        }:
            return self._registro
        raise AttributeError(nombre)

    def send_each_for_multicast(self, peticion):
        self.peticion = peticion
        return SimpleNamespace(
            responses=[SimpleNamespace(success=True) for _ in peticion.tokens],
            success_count=len(peticion.tokens),
            failure_count=0,
        )


def test_mensaje_fcm_lleva_bloque_apns_sin_datos_personales():
    capturador = _Capturador()
    proveedor = ProveedorFCM()

    resultado = proveedor._enviar_lote(capturador, ["tok-ios"], MENSAJE)

    apns = capturador.peticion.apns
    assert resultado.enviados == 1
    assert apns.headers["apns-priority"] == "10"
    assert apns.headers["apns-push-type"] == "alert"
    assert apns.headers["apns-collapse-id"] == MENSAJE.message_id
    assert apns.payload.aps.sound == "default"
    assert capturador.peticion.data == MENSAJE.como_datos()
    assert capturador.peticion.notification.body == "Hay un nuevo aviso de ingreso"
