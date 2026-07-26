"""Plantilla de la incidencia disciplinaria (RF-D01, RF-G04)."""

from __future__ import annotations

from apps.mensajeria.plantillas.base import ContextoEvento, PlantillaBase


class PlantillaIncidencia(PlantillaBase):
    """Aviso de una incidencia registrada por el colegio.

    El detalle completo (observaciones y evidencias) se consulta por API; la
    notificacion solo adelanta la falta, su categoria y quien la reporto, que es
    lo que exige RF-G04.
    """

    tipo = "incidencia"

    def render(self, ctx: ContextoEvento) -> str:
        """Redacta la incidencia con su falta, categoria y responsable."""
        ctx.exigir("estudiante_nombre", "nombre_falta")

        gravedad = " grave" if ctx.es_grave else ""
        detalle = ctx.nombre_falta
        if ctx.categoria:
            detalle = f"{detalle} ({ctx.categoria})"

        frases = [f"Se registró una incidencia{gravedad} de {ctx.estudiante_nombre}: {detalle}."]
        if ctx.reportado_por:
            frases.append(f"Reportada por {ctx.reportado_por}.")
        return " ".join(frases)
