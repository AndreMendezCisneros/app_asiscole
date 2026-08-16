"""Servicios de administración: cuentas, avisos y feature flags."""

from __future__ import annotations

import logging

from django.db.models import Q

from apps.administracion.models import FeatureFlag, VersionApp
from apps.common.errors import RoleNotAllowed, ValidationError
from apps.cuentas.models import (
    CUENTA_ACTIVA,
    CUENTA_SUSPENDIDA,
    PREFIJO_IDENTIDAD_ADMIN,
    SESION_ACTIVA,
    Apoderado,
    SesionActiva,
    partes_identidad_administrador,
)
from apps.cuentas.services import enmascarar_telefono
from apps.cuentas.suspension import forzar_cierre_sesion, reactivar, suspender
from apps.directorio.models import VINCULO_ACTIVO, Directorio
from apps.mensajeria.models import TIPO_AVISO, Mensaje
from apps.mensajeria.plantillas.base import ContextoEvento
from apps.mensajeria.plantillas.registry import renderizar

logger = logging.getLogger("asiscole.administracion")


def tenant_del_admin(admin: Apoderado) -> str:
    """Extrae el tenant_id embebido en `admin:{tenant}:{id_usuario}`."""
    partes = partes_identidad_administrador(admin.telefono)
    if partes is None:
        raise RoleNotAllowed()
    return partes[0]


def _apoderado_del_tenant(apoderado_id: int, tenant_id: str) -> Apoderado:
    """Carga un apoderado solo si tiene vínculo activo en el tenant del admin."""
    apo = Apoderado.objects.filter(pk=apoderado_id).first()
    if apo is None or apo.es_administrador:
        raise ValidationError("No se encontró la cuenta indicada.")
    if not Directorio.objects.filter(
        telefono=apo.telefono,
        tenant_id=tenant_id,
        estado_vinculo=VINCULO_ACTIVO,
    ).exists():
        # Misma respuesta que "no existe": no filtrar por tenant en el mensaje.
        raise ValidationError("No se encontró la cuenta indicada.")
    return apo


def listar_flags() -> dict[str, bool]:
    """Devuelve los flags; garantiza `notas` y `citacion` en false por defecto."""
    FeatureFlag.objects.get_or_create(clave="notas", defaults={"activo": False})
    FeatureFlag.objects.get_or_create(clave="citacion", defaults={"activo": False})
    return {f.clave: f.activo for f in FeatureFlag.objects.all()}


PLATAFORMAS_VERSION = frozenset({"android", "ios"})


def politica_version_app(plataforma: str, version_instalada: int | None) -> dict:
    """Resuelve si la version instalada sigue siendo aceptable.

    El calculo lo hace el servidor y el cliente solo obedece: si la comparacion
    viviera en la app, arreglar un criterio mal puesto exigiria otra publicacion.

    Args:
        plataforma: `android` o `ios`.
        version_instalada: `versionCode` de la cabecera `X-App-Version`. Si no
            llega, no se bloquea a nadie: puede ser un cliente antiguo o una
            cabecera perdida por un proxy.

    Returns:
        El cuerpo de `GET /sistema/version-app` (esquema `VersionApp`).

    Raises:
        ValidationError: Si la plataforma no es una de las soportadas.
    """
    plataforma = (plataforma or "").strip().lower()
    if plataforma not in PLATAFORMAS_VERSION:
        raise ValidationError("La plataforma debe ser android o ios.")

    fila, _ = VersionApp.objects.get_or_create(plataforma=plataforma)

    obligatoria = version_instalada is not None and version_instalada < fila.min_soportada
    disponible = version_instalada is not None and version_instalada < fila.ultima_disponible
    return {
        "plataforma": plataforma,
        "min_soportada": fila.min_soportada,
        "ultima_disponible": fila.ultima_disponible,
        "actualizacion_obligatoria": obligatoria,
        "actualizacion_disponible": disponible,
        "mensaje": fila.mensaje or None,
        "url_tienda": fila.url_tienda or None,
    }


def listar_apoderados(
    *,
    tenant_id: str,
    buscar: str | None = None,
    estado: str | None = None,
    cursor: str | None = None,
    limite: int = 50,
) -> dict:
    """Lista apoderados con al menos un vínculo activo en `tenant_id`."""
    telefonos_tenant = Directorio.objects.filter(
        tenant_id=tenant_id,
        estado_vinculo=VINCULO_ACTIVO,
    ).values_list("telefono", flat=True)

    qs = (
        Apoderado.objects.filter(telefono__in=telefonos_tenant)
        .exclude(telefono__startswith=PREFIJO_IDENTIDAD_ADMIN)
        .exclude(estado="eliminado")
    )
    if estado in (CUENTA_ACTIVA, CUENTA_SUSPENDIDA):
        qs = qs.filter(estado=estado)
    if buscar:
        # Solo busca por alias o id; nunca por teléfono en claro en logs.
        if buscar.isdigit():
            qs = qs.filter(Q(pk=int(buscar)) | Q(nombre_alias__icontains=buscar))
        else:
            qs = qs.filter(nombre_alias__icontains=buscar)
    if cursor and cursor.isdigit():
        qs = qs.filter(pk__lt=int(cursor))

    filas = list(qs.order_by("-pk")[: limite + 1])
    hay_mas = len(filas) > limite
    pagina = filas[:limite]
    items = []
    for apo in pagina:
        sesion = (
            SesionActiva.objects.filter(apoderado=apo, estado=SESION_ACTIVA)
            .order_by("-ultima_actividad_en")
            .first()
        )
        estudiantes = [
            {
                "id": v.id_estudiante,
                "nombre": v.nombre_estudiante,
                "grado": v.grado or "",
                "seccion": v.seccion or "",
                "nivel": v.nivel or "",
                "colegio": v.tenant_id,
                "tenant_id": v.tenant_id,
                "activo": apo.estudiante_activo_id == v.id_estudiante,
            }
            for v in Directorio.objects.filter(
                telefono=apo.telefono,
                tenant_id=tenant_id,
                estado_vinculo=VINCULO_ACTIVO,
            )[:20]
        ]
        items.append(
            {
                "id": apo.pk,
                "alias": apo.nombre_alias,
                "telefono": enmascarar_telefono(apo.telefono),
                "estado": apo.estado,
                "motivo_suspension": apo.motivo_suspension,
                "sesion_activa": sesion is not None,
                "ultimo_dispositivo": sesion.modelo if sesion else None,
                "ultima_actividad_en": (
                    sesion.ultima_actividad_en.isoformat() if sesion else None
                ),
                "estudiantes": estudiantes,
            }
        )
    next_cursor = str(pagina[-1].pk) if hay_mas and pagina else None
    return {"items": items, "next_cursor": next_cursor}


def suspender_cuenta(
    apoderado_id: int,
    *,
    motivo: str,
    actor: str | None,
    tenant_id: str,
    notificar_push: bool = True,
) -> None:
    if not motivo or len(motivo.strip()) < 5:
        raise ValidationError("El motivo debe tener al menos 5 caracteres.")
    apo = _apoderado_del_tenant(apoderado_id, tenant_id)
    suspender(apo, motivo.strip(), actor=actor, notificar_push=notificar_push)


def reactivar_cuenta(
    apoderado_id: int, *, actor: str | None, tenant_id: str
) -> None:
    apo = _apoderado_del_tenant(apoderado_id, tenant_id)
    reactivar(apo, actor=actor)


def cerrar_sesion_cuenta(
    apoderado_id: int, *, actor: str | None, tenant_id: str
) -> None:
    apo = _apoderado_del_tenant(apoderado_id, tenant_id)
    forzar_cierre_sesion(apo, actor=actor)


def enviar_aviso(
    *,
    tenant_id: str,
    texto: str,
    nivel: str | None = None,
    grado: str | None = None,
    seccion: str | None = None,
) -> dict:
    """Crea mensajes tipo aviso filtrados por nivel/grado/sección (RF-B04)."""
    cuerpo = (texto or "").strip()
    if not cuerpo:
        raise ValidationError("El texto del aviso es obligatorio.")

    qs = Directorio.objects.filter(
        estado_vinculo=VINCULO_ACTIVO,
        tenant_id=tenant_id,
    )
    if nivel:
        qs = qs.filter(nivel=nivel)
    if grado:
        qs = qs.filter(grado=grado)
    if seccion:
        qs = qs.filter(seccion=seccion)

    telefonos = list(qs.values_list("telefono", flat=True).distinct())
    apoderados = list(
        Apoderado.objects.filter(telefono__in=telefonos, estado=CUENTA_ACTIVA).exclude(
            telefono__startswith=PREFIJO_IDENTIDAD_ADMIN
        )
    )

    ctx = ContextoEvento(tipo=TIPO_AVISO, texto_libre=cuerpo, colegio="Asiscole")
    redactado = renderizar(TIPO_AVISO, ctx)

    from apps.mensajeria.tasks import enviar_push_mensaje

    creados = 0
    for apo in apoderados:
        mensaje = Mensaje.objects.create(
            apoderado=apo,
            tenant_id=tenant_id,
            id_estudiante=None,
            tipo=TIPO_AVISO,
            texto=redactado,
            metadata={"nivel": nivel, "grado": grado, "seccion": seccion},
            origen_evento=None,
        )
        enviar_push_mensaje.delay(str(mensaje.pk))
        creados += 1

    logger.info(
        "aviso_encolado",
        extra={"destinatarios": creados, "tenant_id": tenant_id},
    )
    return {"destinatarios": creados}
