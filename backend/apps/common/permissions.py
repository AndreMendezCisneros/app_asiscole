"""Permisos por defecto del canal.

DRF se configura para denegar todo salvo que la vista declare lo contrario. Asi
una vista nueva a la que se olvide ponerle `permission_classes` responde 401 en
lugar de quedar abierta.
"""

from __future__ import annotations

from rest_framework.permissions import BasePermission


class DenegarPorDefecto(BasePermission):
    """Deniega siempre. Cada vista debe declarar su permiso explicitamente."""

    def has_permission(self, request, view) -> bool:
        return False

    def has_object_permission(self, request, view, obj) -> bool:
        return False


class PermitirSinToken(BasePermission):
    """Permite el acceso sin `data_token`.

    Solo para las rutas que por definicion no pueden exigirlo: login, health y
    la documentacion del contrato.
    """

    def has_permission(self, request, view) -> bool:
        return True
