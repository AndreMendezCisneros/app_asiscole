"""Autorización: el estudiante_id del cliente siempre se contrastá con el directorio."""

from __future__ import annotations

from apps.common.errors import RoleNotAllowed, StudentLinkNotFound
from apps.cuentas.models import Apoderado
from apps.directorio.models import VINCULO_ACTIVO, Directorio


def vinculo_estudiante(apoderado: Apoderado, estudiante_id: int) -> Directorio:
    """Devuelve el vínculo activo o lanza error del catálogo.

    Raises:
        StudentLinkNotFound: No hay vínculo para esa cuenta y ese estudiante.
        RoleNotAllowed: La cuenta es de administración, no de apoderado.
    """
    if apoderado.es_administrador:
        raise RoleNotAllowed()
    vinculo = (
        Directorio.objects.filter(
            telefono=apoderado.telefono,
            id_estudiante=estudiante_id,
            estado_vinculo=VINCULO_ACTIVO,
        )
        .order_by("tenant_id")
        .first()
    )
    if vinculo is None:
        raise StudentLinkNotFound()
    return vinculo
