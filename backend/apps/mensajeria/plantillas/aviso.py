"""Plantilla del aviso institucional (RF-D01, RF-J03)."""

from __future__ import annotations

from apps.mensajeria.plantillas.base import ContextoEvento, PlantillaBase


class PlantillaAviso(PlantillaBase):
    """Comunicado que la administracion del colegio envia a varios apoderados.

    El cuerpo lo escribe una persona, asi que la plantilla solo lo encabeza y lo
    limpia. No nace de un evento del outbox: su `origen_evento` es `NULL` y por
    eso un mismo texto puede enviarse mas de una vez.
    """

    tipo = "aviso"

    def render(self, ctx: ContextoEvento) -> str:
        """Antepone el encabezado del colegio al texto del comunicado."""
        ctx.exigir("texto_libre")

        cuerpo = " ".join((ctx.texto_libre or "").split())
        encabezado = f"Comunicado de {ctx.colegio}" if ctx.colegio else "Comunicado del colegio"
        return f"{encabezado}: {cuerpo}"
