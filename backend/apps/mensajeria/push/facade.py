"""Fachada de envio de notificaciones push.

Unifica FCM y APNs detras de una sola llamada: quien envia no sabe (ni le
importa) en que plataforma esta cada dispositivo. Dos cosas resuelve esta capa:

* **Multicast.** Los tokens se agrupan por plataforma y se mandan en una sola
  peticion por proveedor. En las horas pico (entrada de 07:00 a 08:00 y salida
  del mediodia) un aviso institucional puede abarcar miles de dispositivos y no
  se puede abrir una conexion por cada uno.
* **Idempotencia por `message_id`.** Un reintento de Celery o dos workers que
  toman la misma fila no pueden producir dos notificaciones. La reserva vive en
  la cache compartida (Redis) y se libera si el envio falla, para que el
  reintento si pueda salir.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable, Sequence

from django.core.cache import cache

from apps.mensajeria.push.apns import ProveedorAPNs
from apps.mensajeria.push.base import MensajePush, ProveedorPush, ResultadoEnvio
from apps.mensajeria.push.fcm import ProveedorFCM

logger = logging.getLogger("asiscole.mensajeria.push")

#: Cuanto se recuerda que un mensaje ya se notifico.
VENTANA_IDEMPOTENCIA_SEGUNDOS = 6 * 60 * 60


def _clave_idempotencia(message_id: str) -> str:
    return f"push:enviado:{message_id}"


class ServicioPush:
    """Envio unificado a Android e iOS."""

    def __init__(
        self,
        proveedor_android: ProveedorPush | None = None,
        proveedor_ios: ProveedorPush | None = None,
    ) -> None:
        self.proveedores: dict[str, ProveedorPush] = {
            "android": proveedor_android or ProveedorFCM(),
            "ios": proveedor_ios or ProveedorAPNs(),
        }

    def _agrupar(self, tokens: Iterable) -> dict[str, list[str]]:
        """Agrupa los tokens de dispositivo por plataforma.

        Args:
            tokens: Objetos con `token` y `plataforma` (`cuentas.PushToken`), o
                directamente cadenas.

        Returns:
            Diccionario plataforma -> lista de tokens. Un token sin plataforma
            declarada se manda por FCM, que es la mayoritaria del parque.
        """
        grupos: dict[str, list[str]] = {"android": [], "ios": []}
        for elemento in tokens:
            valor = getattr(elemento, "token", elemento)
            if not valor:
                continue
            plataforma = (getattr(elemento, "plataforma", None) or "android").strip().lower()
            grupos.setdefault(plataforma if plataforma in grupos else "android", []).append(valor)
        return grupos

    def _reservar(self, message_id: str) -> bool:
        """Intenta reservar el envio de un mensaje.

        Returns:
            True si se puede enviar. `cache.add` devuelve False solo cuando la
            clave ya existia; si Redis esta caido devuelve None y entonces se
            envia igual: es preferible arriesgar una notificacion repetida a
            dejar al apoderado sin aviso.
        """
        return cache.add(_clave_idempotencia(message_id), 1, VENTANA_IDEMPOTENCIA_SEGUNDOS) is not False

    def _liberar(self, message_id: str) -> None:
        """Suelta la reserva para que el reintento pueda volver a intentarlo."""
        cache.delete(_clave_idempotencia(message_id))

    def enviar(
        self, tokens: Sequence, mensaje: MensajePush, *, idempotente: bool = True
    ) -> ResultadoEnvio:
        """Manda una notificacion a todos los dispositivos de una cuenta.

        Args:
            tokens: Tokens de push (objetos o cadenas).
            mensaje: Carga minima (tipo, `message_id` y deep-link).
            idempotente: Si es True, un `message_id` ya notificado se omite.

        Returns:
            El agregado de los proveedores implicados.

        Raises:
            ErrorDeProveedorPush: Si algun proveedor fallo. La reserva de
                idempotencia se libera antes de propagar.
        """
        grupos = self._agrupar(tokens)
        if not any(grupos.values()):
            return ResultadoEnvio()

        if idempotente and not self._reservar(mensaje.message_id):
            logger.info(
                "push_omitido_duplicado",
                extra={"message_id": mensaje.message_id, "tipo_mensaje": mensaje.tipo},
            )
            return ResultadoEnvio()

        resultado = ResultadoEnvio()
        try:
            for plataforma, lote in grupos.items():
                if not lote:
                    continue
                resultado = resultado.combinar(self.proveedores[plataforma].enviar(lote, mensaje))
        except Exception:
            if idempotente:
                self._liberar(mensaje.message_id)
            raise

        if idempotente and not resultado.hubo_entrega:
            # Nadie lo recibio: no se puede dar por notificado.
            self._liberar(mensaje.message_id)

        logger.info(
            "push_enviado",
            extra={
                "message_id": mensaje.message_id,
                "tipo_mensaje": mensaje.tipo,
                "enviados": resultado.enviados,
                "fallidos": resultado.fallidos,
                "invalidos": len(resultado.tokens_invalidos),
                "simulado": resultado.simulado,
            },
        )
        return resultado

    def enviar_lote(self, envios: Iterable[tuple[Sequence, MensajePush]]) -> ResultadoEnvio:
        """Envia varias notificaciones seguidas reutilizando los proveedores.

        Es lo que usa el aviso institucional: cada apoderado tiene su propio
        `message_id`, pero todos comparten proceso, cliente y conexion.

        Args:
            envios: Pares `(tokens, mensaje)`.

        Returns:
            El agregado de todos los envios. Un fallo aislado no interrumpe el
            recorrido: se cuenta y se sigue con el resto de la tanda.
        """
        total = ResultadoEnvio()
        for tokens, mensaje in envios:
            try:
                total = total.combinar(self.enviar(tokens, mensaje))
            except Exception:  # noqa: BLE001 — un destinatario no puede tumbar la tanda
                total.fallidos += 1
                logger.warning(
                    "push_lote_destinatario_error", extra={"message_id": mensaje.message_id}
                )
        return total


_servicio: ServicioPush | None = None


def servicio_push() -> ServicioPush:
    """Devuelve la instancia compartida del servicio de push.

    Se crea de forma perezosa para no inicializar los SDK al importar el modulo
    (los comandos de gestion y las pruebas no los necesitan).
    """
    global _servicio  # noqa: PLW0603 — singleton del proceso
    if _servicio is None:
        _servicio = ServicioPush()
    return _servicio


def reiniciar_servicio_push() -> None:
    """Olvida la instancia compartida. Solo para pruebas y recarga de settings."""
    global _servicio  # noqa: PLW0603
    _servicio = None
