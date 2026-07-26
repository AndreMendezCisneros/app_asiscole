"""Plantilla de la salida del colegio (RF-D01)."""

from __future__ import annotations

from apps.mensajeria.plantillas.base import ContextoEvento, PlantillaBase


class PlantillaSalida(PlantillaBase):
    """Aviso de que el estudiante ya salio del colegio.

    El colegio distingue tres tipos de salida (`Normal`, `Autorizada`,
    `Sin registro`). Solo la autorizada cambia el texto: es la que el apoderado
    necesita reconocer, porque ocurre fuera del horario habitual.
    """

    tipo = "salida"

    def render(self, ctx: ContextoEvento) -> str:
        """Redacta la salida, senalando si fue autorizada."""
        ctx.exigir("estudiante_nombre", "hora")

        if ctx.salida_autorizada:
            return (
                f"{ctx.estudiante_nombre} salió del colegio a las {ctx.hora} "
                "con una salida autorizada."
            )
        return f"{ctx.estudiante_nombre} salió del colegio a las {ctx.hora}."
