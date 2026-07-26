"""Registro de plantillas por tipo de mensaje.

Anadir un tipo son tres pasos: crear la estrategia, sumarla a
`REGISTRO_PLANTILLAS` y anadir el codigo al enum de `asis_mensaje`. Nada de esto
obliga a publicar una version nueva de la app.

Un tipo sin plantilla registrada hace fallar la operacion de forma explicita
(`PlantillaNoRegistrada`) en lugar de guardar un mensaje vacio: el poller
reintentara el evento y la alerta saldra en el log, que es justo lo que se
quiere si alguien anade un tipo a medias.
"""

from __future__ import annotations

from apps.mensajeria.plantillas.aviso import PlantillaAviso
from apps.mensajeria.plantillas.base import (
    ContextoEvento,
    ErrorDePlantilla,
    PlantillaBase,
    PlantillaNoRegistrada,
)
from apps.mensajeria.plantillas.entrada import PlantillaEntrada
from apps.mensajeria.plantillas.incidencia import PlantillaIncidencia
from apps.mensajeria.plantillas.personalizado import PlantillaPersonalizada
from apps.mensajeria.plantillas.salida import PlantillaSalida

#: Tipo de mensaje -> estrategia que lo redacta.
REGISTRO_PLANTILLAS: dict[str, type[PlantillaBase]] = {
    PlantillaEntrada.tipo: PlantillaEntrada,
    PlantillaSalida.tipo: PlantillaSalida,
    PlantillaIncidencia.tipo: PlantillaIncidencia,
    PlantillaAviso.tipo: PlantillaAviso,
    PlantillaPersonalizada.tipo: PlantillaPersonalizada,
}


def obtener_plantilla(tipo: str) -> PlantillaBase:
    """Devuelve una instancia de la plantilla de ese tipo.

    Args:
        tipo: Codigo del tipo de mensaje.

    Returns:
        La plantilla lista para renderizar.

    Raises:
        PlantillaNoRegistrada: Si el tipo no existe en el registro.
    """
    clase = REGISTRO_PLANTILLAS.get((tipo or "").strip())
    if clase is None:
        raise PlantillaNoRegistrada(f"no hay plantilla registrada para el tipo '{tipo}'")
    return clase()


def renderizar(tipo: str, ctx: ContextoEvento) -> str:
    """Redacta el texto de un mensaje.

    Args:
        tipo: Codigo del tipo de mensaje.
        ctx: Datos del evento ya resueltos.

    Returns:
        El texto final, sin espacios sobrantes en los extremos.

    Raises:
        PlantillaNoRegistrada: El tipo no tiene plantilla.
        ErrorDePlantilla: La plantilla devolvio un texto vacio. Se prefiere
            fallar a dejar una notificacion muda en el telefono del apoderado.
    """
    texto = (obtener_plantilla(tipo).render(ctx) or "").strip()
    if not texto:
        raise ErrorDePlantilla(f"la plantilla '{tipo}' produjo un texto vacio")
    return texto
