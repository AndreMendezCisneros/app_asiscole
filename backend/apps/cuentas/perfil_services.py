"""Perfil, multi-hijo y eliminación de cuenta (RF-I)."""

from __future__ import annotations

import logging
import uuid

from django.db import transaction
from django.utils import timezone

from apps.academico.authz import vinculo_estudiante
from apps.common.errors import StudentLinkNotFound, ValidationError
from apps.cuentas.models import (
    CUENTA_ELIMINADA,
    SESION_ACTIVA,
    SESION_REVOCADA,
    Apoderado,
    Auditoria,
    PushToken,
    SesionActiva,
)
from apps.cuentas.services import construir_perfil
from apps.directorio import services as directorio_svc
from apps.directorio.models import VINCULO_ACTIVO, Directorio

logger = logging.getLogger("asiscole.cuentas.perfil")


def obtener_perfil(apoderado: Apoderado) -> dict:
    return construir_perfil(apoderado, apoderado.estudiante_activo_id)


def actualizar_perfil(
    apoderado: Apoderado,
    *,
    alias: str | None = None,
    estudiante_activo_id: int | None = None,
) -> dict:
    if alias is not None:
        apoderado.nombre_alias = (alias or "").strip() or None
    if estudiante_activo_id is not None:
        vinculo = vinculo_estudiante(apoderado, estudiante_activo_id)
        apoderado.estudiante_activo_id = vinculo.id_estudiante
        apoderado.estudiante_activo_tenant = vinculo.tenant_id
    apoderado.save(
        update_fields=[
            "nombre_alias",
            "estudiante_activo_id",
            "estudiante_activo_tenant",
            "actualizado_en",
        ]
    )
    return obtener_perfil(apoderado)


def listar_estudiantes(apoderado: Apoderado) -> dict:
    """Lista de hijos vinculados (RF-I02)."""
    filas = Directorio.objects.filter(
        telefono=apoderado.telefono, estado_vinculo=VINCULO_ACTIVO
    ).order_by("nombre_estudiante")
    activo = apoderado.estudiante_activo_id
    items = [
        {
            "id": f.id_estudiante,
            "nombre": f.nombre_estudiante,
            "grado": f.grado or "",
            "seccion": f.seccion or "",
            "nivel": f.nivel or "",
            "colegio": f.tenant_id,
            "tenant_id": f.tenant_id,
            "activo": f.id_estudiante == activo,
        }
        for f in filas
    ]
    return {"items": items}


def vincular_estudiante(apoderado: Apoderado, documento: str) -> dict:
    """Vincula un DNI/código adicional si coincide el teléfono (RF-I04)."""
    documento = (documento or "").strip()
    if not documento:
        raise ValidationError("Debes indicar el documento del estudiante.")
    vinculos = directorio_svc.resolver_vinculos(apoderado.telefono)
    hallado = next((v for v in vinculos if v.codigo_barras == documento), None)
    if hallado is None:
        raise StudentLinkNotFound()
    # El resolvedor ya upserta el directorio; devolvemos la forma del contrato.
    if apoderado.estudiante_activo_id is None:
        apoderado.estudiante_activo_id = hallado.id_estudiante
        apoderado.estudiante_activo_tenant = hallado.tenant_id
        apoderado.save(
            update_fields=["estudiante_activo_id", "estudiante_activo_tenant", "actualizado_en"]
        )
    return {
        "id": hallado.id_estudiante,
        "nombre": hallado.nombre_estudiante,
        "grado": hallado.grado or "",
        "seccion": hallado.seccion or "",
        "nivel": hallado.nivel or "",
        "colegio": hallado.tenant_id,
        "tenant_id": hallado.tenant_id,
        "activo": apoderado.estudiante_activo_id == hallado.id_estudiante,
    }


def registrar_push_token(
    apoderado: Apoderado,
    sesion: SesionActiva,
    *,
    token: str,
    plataforma: str,
) -> None:
    if plataforma not in ("android", "ios"):
        raise ValidationError("La plataforma debe ser android o ios.")
    if not (token or "").strip():
        raise ValidationError("El token de push es obligatorio.")
    PushToken.objects.update_or_create(
        apoderado=apoderado,
        device_id=sesion.device_id,
        defaults={
            "token": token.strip(),
            "plataforma": plataforma,
            "activo": True,
        },
    )
    # Si el mensaje se creó antes (push_sin_destinos), se reenvía ahora.
    from apps.mensajeria.tasks import reintentar_push_pendientes

    reintentar_push_pendientes(apoderado)


@transaction.atomic
def eliminar_cuenta(apoderado: Apoderado, documento_estudiante: str) -> None:
    """Anonimiza la cuenta del apoderado (RF-I06). No toca el expediente escolar."""
    documento = (documento_estudiante or "").strip()
    if not documento:
        raise ValidationError("Debes confirmar con el documento del estudiante.")
    existe = Directorio.objects.filter(
        telefono=apoderado.telefono,
        codigo_barras=documento,
        estado_vinculo=VINCULO_ACTIVO,
    ).exists()
    if not existe:
        raise StudentLinkNotFound()

    SesionActiva.objects.filter(apoderado=apoderado, estado=SESION_ACTIVA).update(
        estado=SESION_REVOCADA, ultima_actividad_en=timezone.now()
    )
    PushToken.objects.filter(apoderado=apoderado).update(activo=False)
    Directorio.objects.filter(telefono=apoderado.telefono).update(estado_vinculo="inactivo")

    apoderado.telefono = f"deleted:{uuid.uuid4()}"
    apoderado.nombre_alias = None
    apoderado.estado = CUENTA_ELIMINADA
    apoderado.estudiante_activo_id = None
    apoderado.estudiante_activo_tenant = None
    apoderado.motivo_suspension = None
    apoderado.save()

    Auditoria.objects.create(
        apoderado=apoderado,
        actor=f"apoderado:{apoderado.pk}",
        accion="cuenta_eliminada",
        detalle={},
    )
    logger.info("cuenta_eliminada", extra={"apoderado_id": apoderado.pk})
