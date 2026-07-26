"""Plantillas de los mensajes que recibe el apoderado.

El backend genera el texto y el cliente solo lo renderiza. Cada tipo de mensaje
es una estrategia (`PlantillaBase`) registrada en `REGISTRO_PLANTILLAS`.
"""

from apps.mensajeria.plantillas.base import (
    ContextoEvento,
    DatosDeEventoIncompletos,
    ErrorDePlantilla,
    PlantillaBase,
    PlantillaNoRegistrada,
)
from apps.mensajeria.plantillas.registry import (
    REGISTRO_PLANTILLAS,
    obtener_plantilla,
    renderizar,
)

__all__ = [
    "REGISTRO_PLANTILLAS",
    "ContextoEvento",
    "DatosDeEventoIncompletos",
    "ErrorDePlantilla",
    "PlantillaBase",
    "PlantillaNoRegistrada",
    "obtener_plantilla",
    "renderizar",
]
