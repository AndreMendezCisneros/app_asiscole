"""Plantilla del aviso institucional (RF-D01, RF-J03)."""

from __future__ import annotations

from apps.mensajeria.plantillas.base import ContextoEvento, PlantillaBase


class PlantillaAviso(PlantillaBase):
    """Comunicado institucional: pensión, cita o texto libre.

    El cuerpo lo escribe una persona (o el SIE en `texto_libre`), y la plantilla
    solo lo encabeza según `payload.contexto` (`cita`, `pension` o genérico).
    Los avisos del administrador pueden repetirse (`origen_evento` nulo). Los
    que vienen de ingesta deduplican con `aviso:{id_registro}`.
    """

    tipo = "aviso"

    def render(self, ctx: ContextoEvento) -> str:
        """Antepone el encabezado del colegio al texto del comunicado."""
        ctx.exigir("texto_libre")

        cuerpo = " ".join((ctx.texto_libre or "").split())
        contexto = (ctx.contexto or "").strip().lower()
        if contexto == "cita":
            encabezado = (
                f"Citación de {ctx.colegio}" if ctx.colegio else "Citación del colegio"
            )
        elif contexto == "pension":
            encabezado = (
                f"Aviso de pensión de {ctx.colegio}"
                if ctx.colegio
                else "Aviso de pensión"
            )
        else:
            encabezado = (
                f"Comunicado de {ctx.colegio}" if ctx.colegio else "Comunicado del colegio"
            )
        return f"{encabezado}: {cuerpo}"
