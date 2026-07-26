"""Plantilla del ingreso al colegio (RF-D01)."""

from __future__ import annotations

from apps.mensajeria.plantillas.base import ContextoEvento, PlantillaBase


class PlantillaEntrada(PlantillaBase):
    """Aviso de que el estudiante ya esta dentro del colegio.

    La hora llega formateada (`HH:MM`) desde el trigger del colegio, que ya la
    resolvio en America/Lima; aqui no se convierte ninguna zona horaria.
    """

    tipo = "entrada"

    def render(self, ctx: ContextoEvento) -> str:
        """Redacta el ingreso, distinguiendo la tardanza.

        La tardanza se redacta sobre el ingreso ("su ingreso quedo registrado")
        y no sobre la persona: el payload no trae el genero del estudiante y no
        hay forma correcta de concordar el participio.
        """
        ctx.exigir("estudiante_nombre", "hora")

        if ctx.es_tardanza:
            return (
                f"{ctx.estudiante_nombre} ingresó al colegio a las {ctx.hora} "
                "y su ingreso quedó registrado como tardanza."
            )
        return f"{ctx.estudiante_nombre} ingresó al colegio a las {ctx.hora}."
