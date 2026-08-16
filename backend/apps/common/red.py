"""Utilidades de red compartidas por las vistas."""

from __future__ import annotations

from rest_framework.request import Request


def ip_de(request: Request) -> str | None:
    """Devuelve la IP de origen, respetando el proxy inverso.

    Con un solo proxy de confianza (Caddy), el hop anadido es el ultimo de
    `X-Forwarded-For`. Tomar el primero permitiria spoofing del cliente.
    La IP es un dato personal: se hashea antes de cache/BD; nunca en logs.

    Si algun dia se pone Cloudflare delante de Caddy, hay dos hops y esta
    funcion debe leer `CF-Connecting-IP`.
    """
    reenviada = request.headers.get("X-Forwarded-For", "")
    if reenviada:
        partes = [p.strip() for p in reenviada.split(",") if p.strip()]
        if partes:
            return partes[-1]
    return request.META.get("REMOTE_ADDR")
