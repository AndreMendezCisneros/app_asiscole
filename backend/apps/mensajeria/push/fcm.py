"""Proveedor de push para Android (Firebase Cloud Messaging).

Degradacion controlada: si `FCM_CREDENTIALS_PATH` no apunta a un fichero de
credenciales, o si el SDK de Firebase no esta instalado, el proveedor entra en
**modo simulado**: registra el envio en el log y devuelve el recuento como si
hubiera salido. Asi el entorno de desarrollo y la suite de pruebas funcionan sin
secretos, que es la unica forma de que un backend multi-tenant se pueda levantar
en local.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Sequence

from django.conf import settings

from apps.mensajeria.push.base import (
    ErrorDeProveedorPush,
    MensajePush,
    ProveedorPush,
    ResultadoEnvio,
)

logger = logging.getLogger("asiscole.mensajeria.push")

#: Tope de tokens por llamada. FCM admite 500 por multicast.
TAMANO_MULTICAST = 500


class ProveedorFCM(ProveedorPush):
    """Envio a dispositivos Android."""

    plataforma = "android"

    def __init__(self) -> None:
        self._cliente = None
        self._cliente_resuelto = False

    def disponible(self) -> bool:
        """True si hay credenciales legibles y SDK para usarlas."""
        return self._obtener_cliente() is not None

    def _ruta_credenciales(self) -> str:
        return (getattr(settings, "FCM_CREDENTIALS_PATH", "") or "").strip()

    def _obtener_cliente(self):
        """Inicializa el SDK de Firebase una sola vez, si se puede.

        Returns:
            El modulo `firebase_admin.messaging` listo para usar, o `None` si
            falta la credencial o la dependencia.
        """
        if self._cliente_resuelto:
            return self._cliente

        self._cliente_resuelto = True
        ruta = self._ruta_credenciales()
        if not ruta or not os.path.isfile(ruta):
            return None

        try:
            import firebase_admin  # noqa: PLC0415 — dependencia opcional
            from firebase_admin import credentials, messaging  # noqa: PLC0415
        except ImportError:
            logger.warning("push_fcm_sdk_ausente", extra={"proveedor": "fcm"})
            return None

        try:
            if not firebase_admin._apps:  # noqa: SLF001 — el SDK no expone otra sonda
                firebase_admin.initialize_app(credentials.Certificate(ruta))
        except Exception:  # noqa: BLE001 — credencial invalida: se degrada, no se cae
            logger.warning("push_fcm_credencial_invalida", extra={"proveedor": "fcm"})
            return None

        self._cliente = messaging
        return self._cliente

    def enviar(self, tokens: Sequence[str], mensaje: MensajePush) -> ResultadoEnvio:
        """Envia por multicast, en lotes de `TAMANO_MULTICAST`."""
        destinos = [token for token in tokens if token]
        if not destinos:
            return ResultadoEnvio()

        messaging = self._obtener_cliente()
        if messaging is None:
            return self._simular(destinos, mensaje)

        resultado = ResultadoEnvio()
        for inicio in range(0, len(destinos), TAMANO_MULTICAST):
            lote = destinos[inicio : inicio + TAMANO_MULTICAST]
            resultado = resultado.combinar(self._enviar_lote(messaging, lote, mensaje))
        return resultado

    def _enviar_lote(self, messaging, lote: list[str], mensaje: MensajePush) -> ResultadoEnvio:
        """Manda un lote y traduce la respuesta del SDK a `ResultadoEnvio`."""
        try:
            # Solo `data` + prioridad alta: la app muestra la notificación local
            # (logo, canal, sonido) tanto en foreground como en background/killed.
            # El bloque `notification` de FCM lo deja al sistema (icono genérico)
            # y en MIUI a menudo no aparece si el proceso está cerrado.
            peticion = messaging.MulticastMessage(
                tokens=lote,
                data=mensaje.como_datos(),
                android=messaging.AndroidConfig(
                    priority="high",
                    collapse_key=mensaje.message_id,
                ),
            )
            respuesta = messaging.send_each_for_multicast(peticion)
        except Exception as exc:  # noqa: BLE001 — el SDK lanza jerarquias propias
            raise ErrorDeProveedorPush("fallo el envio por FCM") from exc

        invalidos: list[str] = []
        for token, detalle in zip(lote, getattr(respuesta, "responses", []), strict=False):
            if getattr(detalle, "success", False):
                continue
            if _token_muerto(getattr(detalle, "exception", None)):
                invalidos.append(token)

        enviados = int(getattr(respuesta, "success_count", 0))
        fallidos = int(getattr(respuesta, "failure_count", 0))
        return ResultadoEnvio(
            enviados=enviados,
            fallidos=max(0, fallidos - len(invalidos)),
            tokens_invalidos=invalidos,
        )

    def _simular(self, destinos: list[str], mensaje: MensajePush) -> ResultadoEnvio:
        """Registra el envio sin salir a la red.

        Solo se loguean identificadores tecnicos: ni el token completo ni nada
        del contenido del mensaje.
        """
        logger.info(
            "push_simulado",
            extra={
                "proveedor": "fcm",
                "destinos": len(destinos),
                "message_id": mensaje.message_id,
                "tipo_mensaje": mensaje.tipo,
            },
        )
        return ResultadoEnvio(enviados=len(destinos), simulado=True)


def _cuerpo_generico(tipo: str) -> str:
    """Texto visible en la bandeja del sistema; nunca datos del estudiante."""
    return {
        "entrada": "Hay un nuevo aviso de ingreso",
        "salida": "Hay un nuevo aviso de salida",
        "incidencia": "Hay una nueva incidencia",
        "aviso": "Tienes un nuevo aviso del colegio",
    }.get((tipo or "").strip().lower(), "Tienes un nuevo mensaje")


def _token_muerto(excepcion: object) -> bool:
    """Indica si el error del proveedor significa "este token ya no sirve".

    Se mira el codigo del error y no su texto para no depender del idioma ni de
    la version del SDK.
    """
    if excepcion is None:
        return False
    codigo = str(getattr(excepcion, "code", "") or "").upper()
    return codigo in {"UNREGISTERED", "INVALID_ARGUMENT", "NOT_FOUND", "SENDER_ID_MISMATCH"}
