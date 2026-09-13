"""Plantilla de la incidencia disciplinaria (RF-D01, RF-G04)."""

from __future__ import annotations

from apps.mensajeria.plantillas.base import ContextoEvento, PlantillaBase


class PlantillaIncidencia(PlantillaBase):
    """Aviso de una incidencia registrada por el colegio.

    Adelanta la falta, su categoria, quien la reporto y, si el auxiliar las
    escribio, las observaciones. Las evidencias se consultan por API (RF-G04).
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
        observaciones = (ctx.observaciones or "").strip()
        if observaciones:
            frases.append(f"Observaciones: {observaciones}")
        return " ".join(frases)
