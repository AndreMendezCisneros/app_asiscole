"""Proveedor de push para iOS (Apple Push Notification service).

Igual que FCM, degrada a **modo simulado** cuando falta cualquiera de los
secretos (`APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`) o el
cliente HTTP/2 necesario para hablar con Apple.

El token de autorizacion (JWT ES256 firmado con la clave `.p8`) si se construye
aqui, porque solo necesita PyJWT, que ya es dependencia del proyecto. Lo unico
que falta para el envio real es el transporte HTTP/2; mientras no este, el
proveedor se comporta como simulado y lo deja dicho en el log, de modo que nadie
confunda "no configurado" con "entregado".
"""

from __future__ import annotations

import logging
import os
import time
from collections.abc import Sequence

from django.conf import settings

from apps.mensajeria.push.base import (
    ErrorDeProveedorPush,
    MensajePush,
    ProveedorPush,
    ResultadoEnvio,
)

logger = logging.getLogger("asiscole.mensajeria.push")

#: Vida del JWT de autorizacion. Apple exige renovarlo al menos cada hora.
VIGENCIA_TOKEN_SEGUNDOS = 45 * 60


class ProveedorAPNs(ProveedorPush):
    """Envio a dispositivos iOS."""

    plataforma = "ios"

    def __init__(self) -> None:
        self._jwt: str | None = None
        self._jwt_emitido_en: float = 0.0

    def _configuracion(self) -> dict[str, str]:
        return {
            "key_path": (getattr(settings, "APNS_KEY_PATH", "") or "").strip(),
            "key_id": (getattr(settings, "APNS_KEY_ID", "") or "").strip(),
            "team_id": (getattr(settings, "APNS_TEAM_ID", "") or "").strip(),
            "topic": (getattr(settings, "APNS_TOPIC", "") or "").strip(),
        }

    def disponible(self) -> bool:
        """True si estan los cuatro secretos y la clave existe en disco."""
        config = self._configuracion()
        if not all(config.values()):
            return False
        return os.path.isfile(config["key_path"])

    def token_autorizacion(self) -> str | None:
        """Devuelve el JWT ES256 que Apple pide en cada peticion.

        Se cachea en memoria del proceso hasta `VIGENCIA_TOKEN_SEGUNDOS`: Apple
        rechaza a quien lo renueva en cada envio.

        Returns:
            El token firmado, o `None` si no hay credenciales usables.
        """
        if not self.disponible():
            return None

        ahora = time.time()
        if self._jwt and (ahora - self._jwt_emitido_en) < VIGENCIA_TOKEN_SEGUNDOS:
            return self._jwt

        config = self._configuracion()
        try:
            import jwt  # noqa: PLC0415 — PyJWT ya es dependencia del backend

            with open(config["key_path"], "rb") as clave:
                self._jwt = jwt.encode(
                    {"iss": config["team_id"], "iat": int(ahora)},
                    clave.read(),
                    algorithm="ES256",
                    headers={"kid": config["key_id"]},
                )
        except Exception:  # noqa: BLE001 — clave ilegible o mal formada
            logger.warning("push_apns_credencial_invalida", extra={"proveedor": "apns"})
            return None

        self._jwt_emitido_en = ahora
        return self._jwt

    def enviar(self, tokens: Sequence[str], mensaje: MensajePush) -> ResultadoEnvio:
        """Envia la notificacion a los dispositivos iOS del lote."""
        destinos = [token for token in tokens if token]
        if not destinos:
            return ResultadoEnvio()

        autorizacion = self.token_autorizacion()
        cliente = self._cliente_http2()
        if autorizacion is None or cliente is None:
            return self._simular(destinos, mensaje)

        try:
            return self._enviar_real(cliente, autorizacion, destinos, mensaje)
        except ErrorDeProveedorPush:
            raise
        except Exception as exc:  # noqa: BLE001
            raise ErrorDeProveedorPush("fallo el envio por APNs") from exc

    def _cliente_http2(self):
        """Devuelve el cliente HTTP/2 para hablar con Apple, si lo hay.

        APNs solo acepta HTTP/2 y ninguna dependencia actual del backend lo
        habla. Cuando se anada (por ejemplo `httpx[http2]`), este metodo es el
        unico punto que cambia.
        """
        try:
            import httpx  # noqa: PLC0415 — dependencia opcional
        except ImportError:
            return None
        return httpx

    def _enviar_real(self, httpx, autorizacion: str, destinos: list[str], mensaje: MensajePush):
        """Publica la notificacion en APNs, un dispositivo por peticion."""
        config = self._configuracion()
        cuerpo = {
            # `content-available` despierta a la app para que descargue el
            # mensaje por API. Sin `alert`: el texto no viaja en el push.
            "aps": {"content-available": 1, "sound": ""},
            **mensaje.como_datos(),
        }
        encabezados_base = {
            "authorization": f"bearer {autorizacion}",
            "apns-topic": config["topic"],
            "apns-push-type": "background",
            "apns-priority": "5",
            # Idempotencia: Apple colapsa las entregas con el mismo id.
            "apns-collapse-id": mensaje.message_id,
        }

        resultado = ResultadoEnvio()
        with httpx.Client(http2=True, base_url="https://api.push.apple.com", timeout=10) as cliente:
            for token in destinos:
                respuesta = cliente.post(
                    f"/3/device/{token}", json=cuerpo, headers=encabezados_base
                )
                if respuesta.status_code == 200:
                    resultado.enviados += 1
                elif respuesta.status_code in (400, 410):
                    # 410 Unregistered y 400 BadDeviceToken: el token murio.
                    resultado.tokens_invalidos.append(token)
                else:
                    resultado.fallidos += 1
        return resultado

    def _simular(self, destinos: list[str], mensaje: MensajePush) -> ResultadoEnvio:
        """Registra el envio sin salir a la red, con datos solo tecnicos."""
        logger.info(
            "push_simulado",
            extra={
                "proveedor": "apns",
                "destinos": len(destinos),
                "message_id": mensaje.message_id,
                "tipo_mensaje": mensaje.tipo,
            },
        )
        return ResultadoEnvio(enviados=len(destinos), simulado=True)
