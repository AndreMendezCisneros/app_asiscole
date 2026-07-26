"""Plantilla del mensaje personalizado a un apoderado concreto (RF-J04)."""

from __future__ import annotations

from apps.mensajeria.plantillas.base import ContextoEvento, PlantillaBase


class PlantillaPersonalizada(PlantillaBase):
    """Mensaje que un administrador dirige a un apoderado.

    A diferencia del aviso, va a una sola cuenta y suele responder a una
    gestion previa, asi que se entrega tal cual lo escribio el colegio: anadirle
    un encabezado generico lo volveria mas frio y menos util.
    """

    tipo = "personalizado"

    def render(self, ctx: ContextoEvento) -> str:
        """Devuelve el texto del administrador, normalizando los espacios."""
        ctx.exigir("texto_libre")
        return " ".join((ctx.texto_libre or "").split())
