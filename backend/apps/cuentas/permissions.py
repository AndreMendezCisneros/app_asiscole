"""Permisos del canal.

DRF deniega por defecto (`apps.common.permissions.DenegarPorDefecto`), asi que
cada vista declara el permiso que necesita. Los de aqui comprueban tres cosas:
que la peticion trae un token del tipo correcto, que hay una sesion viva detras
y que el rol es el que corresponde.

La verificacion dura (firma, vigencia y estado de la sesion) ya la hizo la clase
de autenticacion; estos permisos solo miran el resultado.
"""

from __future__ import annotations

from rest_framework.permissions import BasePermission

from apps.common.errors import RoleNotAllowed
from apps.cuentas import tokens
from apps.cuentas.models import ROL_APODERADO, ROLES_ADMINISTRACION


def _claims(request) -> dict:
    """Devuelve los claims que dejo la autenticacion, o un diccionario vacio."""
    return getattr(request, "claims", None) or {}


def _hay_sesion(request) -> bool:
    """True si la peticion quedo autenticada con una sesion viva."""
    return getattr(request, "apoderado", None) is not None and getattr(request, "sesion", None) is not None


class _PermisoPorTipoDeToken(BasePermission):
    """Base: exige sesion viva y un `typ` concreto."""

    tipo_esperado: str = ""

    def has_permission(self, request, view) -> bool:
        return _hay_sesion(request) and _claims(request).get("typ") == self.tipo_esperado


class EsApoderadoConDataToken(_PermisoPorTipoDeToken):
    """Apoderado autenticado con `data_token`: el permiso de todo endpoint de negocio."""

    tipo_esperado = tokens.TIPO_DATOS

    def has_permission(self, request, view) -> bool:
        if not super().has_permission(request, view):
            return False
        return _claims(request).get("role") == ROL_APODERADO


class EsApoderadoConSessionToken(_PermisoPorTipoDeToken):
    """Apoderado autenticado con `session_token`: solo para `/auth/*`."""

    tipo_esperado = tokens.TIPO_SESION


class EsAdministrador(BasePermission):
    """Usuario de administracion del colegio (RF-B01, RF-B04).

    Solo los roles `Admin`, `Director` y `Supervisor` de la tabla `usuarios`
    llegan aqui, y el rol viaja en el claim `role` del token.
    """

    def has_permission(self, request, view) -> bool:
        if not _hay_sesion(request):
            return False
        rol = _claims(request).get("role")
        if rol in ROLES_ADMINISTRACION:
            return True
        # Un apoderado autenticado que toca una ruta de administracion recibe
        # 403 ROLE_NOT_ALLOWED, no un 401 generico.
        raise RoleNotAllowed()
