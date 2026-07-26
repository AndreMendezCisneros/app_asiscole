"""Contrato de los proveedores de notificaciones push.

DECISION DE DISENO (Ley N.o 29733, datos de menores): **el payload del push es
minimo**. Viajan tres cosas y nada mas:

* `tipo`: para que la app elija el icono y el canal de notificacion.
* `message_id`: el UUID de `asis_mensaje`. Da idempotencia en el cliente (si la
  notificacion llega dos veces se muestra una sola) y es lo que se consulta.
* `destino`: identificador del deep-link, por ejemplo `mensajes/<uuid>`.

El texto NO viaja en el push. Ni el nombre del estudiante, ni la falta, ni la
hora. Un push atraviesa infraestructura de terceros (FCM y APNs) y queda en sus
registros; el contenido completo se obtiene despues por el API, con el
`data_token` del apoderado. La consecuencia practica es que la notificacion se
muestra con un texto generico hasta que la app resuelve el mensaje, y eso se
acepta a cambio de no filtrar datos de un menor.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Sequence
from dataclasses import dataclass, field


@dataclass(frozen=True)
class MensajePush:
    """Carga util de una notificacion.

    Attributes:
        message_id: UUID del mensaje en `asis_mensaje`, en texto.
        tipo: Tipo del mensaje (`entrada`, `salida`, ...).
        destino: Ruta del deep-link dentro de la app.
    """

    message_id: str
    tipo: str
    destino: str

    def como_datos(self) -> dict[str, str]:
        """Devuelve el diccionario `data` que se manda al proveedor.

        Returns:
            Solo claves tecnicas. Cualquier campo adicional tendria que pasar
            antes por la regla de minimizacion.
        """
        return {
            "tipo": self.tipo,
            "message_id": self.message_id,
            "destino": self.destino,
        }


@dataclass
class ResultadoEnvio:
    """Resultado de un envio, agregable entre proveedores.

    Attributes:
        enviados: Cuantos tokens aceptaron la notificacion.
        fallidos: Cuantos fallaron por un motivo recuperable.
        tokens_invalidos: Tokens que el proveedor declaro muertos (app
            desinstalada, token rotado). El llamador los desactiva.
        simulado: True si no habia credenciales y el envio solo se registro en
            el log. Permite que el entorno de desarrollo funcione sin secretos.
    """

    enviados: int = 0
    fallidos: int = 0
    tokens_invalidos: list[str] = field(default_factory=list)
    simulado: bool = False

    @property
    def hubo_entrega(self) -> bool:
        """True si al menos un dispositivo recibio la notificacion."""
        return self.enviados > 0

    def combinar(self, otro: ResultadoEnvio) -> ResultadoEnvio:
        """Suma el resultado de otro proveedor al propio."""
        return ResultadoEnvio(
            enviados=self.enviados + otro.enviados,
            fallidos=self.fallidos + otro.fallidos,
            tokens_invalidos=[*self.tokens_invalidos, *otro.tokens_invalidos],
            # Basta con que un tramo sea real para que el envio no sea simulado
            # del todo; el log lo refleja para no dar por entregado lo que no lo esta.
            simulado=self.simulado and otro.simulado,
        )


class ErrorDeProveedorPush(Exception):
    """Fallo recuperable del proveedor: la tarea reintenta con backoff."""


class ProveedorPush(ABC):
    """Interfaz de un proveedor concreto (FCM, APNs)."""

    #: Plataforma de los tokens que atiende (`android` o `ios`).
    plataforma: str = ""

    @abstractmethod
    def disponible(self) -> bool:
        """True si hay credenciales y cliente para enviar de verdad."""

    @abstractmethod
    def enviar(self, tokens: Sequence[str], mensaje: MensajePush) -> ResultadoEnvio:
        """Envia la notificacion a un lote de tokens (multicast).

        Args:
            tokens: Tokens de dispositivo de esa plataforma.
            mensaje: Carga minima a entregar.

        Returns:
            El recuento del envio y los tokens que hay que dar de baja.

        Raises:
            ErrorDeProveedorPush: Fallo de red o del servicio. Nunca deja el
                mensaje de la bandeja en un estado intermedio: la bandeja ya
                esta persistida antes de llegar aqui.
        """
