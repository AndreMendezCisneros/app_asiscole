"""Modelos de cuentas y sesiones (BD central, tablas `asis_*`).

Replican `db/migrations/002_central_schema.sql`. Lo importante de este modulo:

* La identidad del apoderado es el telefono en E.164. No hay contrasena: el
  login es telefono + `codigo_barras` del estudiante (ADR-01, ADR-07).
* `asis_sesion_activa` es el almacen de sesion propio del canal, con 10 dias y
  `device_id`. No tiene nada que ver con `app_sesiones` del sistema web (ADR-02).
* El indice unico parcial `asis_uniq_sesion_activa` es la garantia dura de la
  sesion unica (RNF-02): un segundo login se DENIEGA, nunca reemplaza.
"""

from __future__ import annotations

import uuid

from django.db import models
from django.utils import timezone

# --- Estados de la cuenta -----------------------------------------------------
CUENTA_ACTIVA = "activo"
CUENTA_SUSPENDIDA = "suspendido"
CUENTA_ELIMINADA = "eliminado"
ESTADOS_CUENTA = (
    (CUENTA_ACTIVA, "Activa"),
    (CUENTA_SUSPENDIDA, "Suspendida"),
    (CUENTA_ELIMINADA, "Eliminada"),
)

# --- Estados de la sesion -----------------------------------------------------
#: Solo `active` ocupa el indice unico parcial; el valor en ingles viene del
#: esquema canonico y se respeta tal cual.
SESION_ACTIVA = "active"
SESION_REVOCADA = "revocada"
SESION_EXPIRADA = "expirada"
SESION_TRANSFERIDA = "transferida"

# --- Estados de la transferencia ---------------------------------------------
TRANSFERENCIA_PENDIENTE = "pending"
TRANSFERENCIA_APROBADA = "approved"
TRANSFERENCIA_RECHAZADA = "rejected"
TRANSFERENCIA_EXPIRADA = "expired"
ESTADOS_TRANSFERENCIA = (
    (TRANSFERENCIA_PENDIENTE, "Pendiente"),
    (TRANSFERENCIA_APROBADA, "Aprobada"),
    (TRANSFERENCIA_RECHAZADA, "Rechazada"),
    (TRANSFERENCIA_EXPIRADA, "Expirada"),
)

# --- Roles --------------------------------------------------------------------
#: Rol del apoderado en los tokens del canal.
ROL_APODERADO = "apoderado"
#: Roles del colegio que pueden entrar por `/auth/admin/login` (RF-B01).
ROLES_ADMINISTRACION = ("Admin", "Director", "Supervisor")

#: Prefijo de la identidad sintetica de un administrador dentro de
#: `asis_apoderado`. El esquema central no tiene tabla propia de administrador y
#: la politica de sesion unica debe ser la misma, asi que la cuenta del admin se
#: guarda aqui con una identidad que nunca puede colisionar con un telefono.
PREFIJO_IDENTIDAD_ADMIN = "admin:"


def identidad_administrador(tenant_id: str, id_usuario: int) -> str:
    """Construye la identidad sintetica de un administrador de colegio.

    Args:
        tenant_id: Colegio al que pertenece el usuario.
        id_usuario: `usuarios.id_usuario` en la BD de ese colegio.

    Returns:
        Una cadena `admin:{tenant}:{id}`, que se guarda en el campo `telefono`.
    """
    return f"{PREFIJO_IDENTIDAD_ADMIN}{tenant_id}:{id_usuario}"


def partes_identidad_administrador(identidad: str) -> tuple[str, int] | None:
    """Deshace `identidad_administrador`.

    Returns:
        La tupla `(tenant_id, id_usuario)`, o `None` si no es una identidad de
        administrador.
    """
    if not identidad or not identidad.startswith(PREFIJO_IDENTIDAD_ADMIN):
        return None
    resto = identidad[len(PREFIJO_IDENTIDAD_ADMIN) :]
    tenant_id, _, crudo = resto.rpartition(":")
    if not tenant_id or not crudo.isdigit():
        return None
    return tenant_id, int(crudo)


class Apoderado(models.Model):
    """Cuenta del canal (`asis_apoderado`).

    Attributes:
        telefono: Identidad de la cuenta en E.164. Para un administrador lleva
            la identidad sintetica `admin:{tenant}:{id}`.
        estado: `activo`, `suspendido` o `eliminado` (RF-I06).
    """

    telefono = models.TextField(unique=True, verbose_name="Telefono E.164 o identidad")
    nombre_alias = models.TextField(null=True, blank=True, verbose_name="Alias para mostrar")
    estado = models.TextField(default=CUENTA_ACTIVA, choices=ESTADOS_CUENTA)
    motivo_suspension = models.TextField(null=True, blank=True)
    suspendido_en = models.DateTimeField(null=True, blank=True)
    estudiante_activo_id = models.IntegerField(null=True, blank=True)
    estudiante_activo_tenant = models.TextField(null=True, blank=True)
    creado_en = models.DateTimeField(default=timezone.now)
    actualizado_en = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "asis_apoderado"
        verbose_name = "Apoderado"
        verbose_name_plural = "Apoderados"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(estado__in=[CUENTA_ACTIVA, CUENTA_SUSPENDIDA, CUENTA_ELIMINADA]),
                name="asis_apoderado_estado_valido",
            ),
        ]

    def __str__(self) -> str:
        return f"apoderado:{self.pk}"

    @property
    def es_administrador(self) -> bool:
        """True si la cuenta corresponde a un usuario de administracion."""
        return self.telefono.startswith(PREFIJO_IDENTIDAD_ADMIN)

    @property
    def activo(self) -> bool:
        """True si la cuenta puede iniciar sesion y consultar datos."""
        return self.estado == CUENTA_ACTIVA


class SesionActiva(models.Model):
    """Sesion del canal, una sola activa por cuenta (`asis_sesion_activa`).

    El `jti` es lo que revoca: el JWT no se guarda, solo su identificador. El
    `data_token` lleva ese mismo valor en su claim `sid`, de modo que cerrar la
    sesion invalida al instante los dos tokens.
    """

    apoderado = models.ForeignKey(
        Apoderado,
        on_delete=models.CASCADE,
        db_column="apoderado_id",
        related_name="sesiones",
    )
    device_id = models.TextField()
    jti = models.UUIDField(unique=True, default=uuid.uuid4)
    modelo = models.TextField(null=True, blank=True)
    sistema_operativo = models.TextField(null=True, blank=True)
    estado = models.TextField(default=SESION_ACTIVA)
    creada_en = models.DateTimeField(default=timezone.now)
    ultima_actividad_en = models.DateTimeField(default=timezone.now)
    expira_en = models.DateTimeField()

    class Meta:
        db_table = "asis_sesion_activa"
        verbose_name = "Sesion activa"
        verbose_name_plural = "Sesiones activas"
        constraints = [
            # RNF-02: la BD garantiza una unica sesion activa por apoderado. La
            # carrera entre dos logins simultaneos se resuelve aqui, no en
            # Python: el perdedor recibe IntegrityError y el servicio lo traduce
            # en 409 SESSION_ALREADY_ACTIVE.
            models.UniqueConstraint(
                fields=["apoderado"],
                condition=models.Q(estado=SESION_ACTIVA),
                name="asis_uniq_sesion_activa",
            ),
        ]
        indexes = [
            models.Index(
                fields=["expira_en"],
                condition=models.Q(estado=SESION_ACTIVA),
                name="asis_idx_sesion_expira",
            ),
        ]

    def __str__(self) -> str:
        return f"sesion:{self.pk}"

    @property
    def vigente(self) -> bool:
        """True si la sesion sigue activa y no ha vencido."""
        return self.estado == SESION_ACTIVA and self.expira_en > timezone.now()


class TransferenciaSesion(models.Model):
    """Solicitud de cambio de dispositivo (`asis_transferencia_sesion`, RF-A09).

    La pide el equipo nuevo tras recibir un 409 y la aprueba o rechaza el equipo
    que tiene la sesion viva. Vence a los `TRANSFER_REQUEST_TTL_MINUTES`.
    """

    apoderado = models.ForeignKey(
        Apoderado,
        on_delete=models.CASCADE,
        db_column="apoderado_id",
        related_name="transferencias",
    )
    from_device_id = models.TextField(null=True, blank=True)
    to_device_id = models.TextField()
    estado = models.TextField(default=TRANSFERENCIA_PENDIENTE, choices=ESTADOS_TRANSFERENCIA)
    creada_en = models.DateTimeField(default=timezone.now)
    expira_en = models.DateTimeField()

    class Meta:
        db_table = "asis_transferencia_sesion"
        verbose_name = "Transferencia de sesion"
        verbose_name_plural = "Transferencias de sesion"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(
                    estado__in=[
                        TRANSFERENCIA_PENDIENTE,
                        TRANSFERENCIA_APROBADA,
                        TRANSFERENCIA_RECHAZADA,
                        TRANSFERENCIA_EXPIRADA,
                    ]
                ),
                name="asis_transferencia_estado_valido",
            ),
            # Una sola solicitud pendiente por apoderado: evita que varios
            # equipos inunden de pedidos al dispositivo con la sesion.
            models.UniqueConstraint(
                fields=["apoderado"],
                condition=models.Q(estado=TRANSFERENCIA_PENDIENTE),
                name="asis_uniq_transferencia_pendiente",
            ),
        ]

    def __str__(self) -> str:
        return f"transferencia:{self.pk}"

    @property
    def vencida(self) -> bool:
        """True si ya paso su tiempo de vida."""
        return self.expira_en <= timezone.now()


class PushToken(models.Model):
    """Token de notificaciones de un dispositivo (`asis_push_token`)."""

    PLATAFORMAS = (("android", "Android"), ("ios", "iOS"))

    apoderado = models.ForeignKey(
        Apoderado,
        on_delete=models.CASCADE,
        db_column="apoderado_id",
        related_name="push_tokens",
    )
    device_id = models.TextField()
    token = models.TextField()
    plataforma = models.TextField(null=True, blank=True, choices=PLATAFORMAS)
    activo = models.BooleanField(default=True)
    actualizado_en = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "asis_push_token"
        verbose_name = "Token de push"
        verbose_name_plural = "Tokens de push"
        constraints = [
            models.UniqueConstraint(
                fields=["apoderado", "device_id"], name="asis_push_token_unico"
            ),
            models.CheckConstraint(
                condition=models.Q(plataforma__isnull=True)
                | models.Q(plataforma__in=["android", "ios"]),
                name="asis_push_token_plataforma_valida",
            ),
        ]

    def __str__(self) -> str:
        return f"push_token:{self.pk}"


class ConfirmacionIncidencia(models.Model):
    """Confirmación de lectura de una incidencia (`asis_confirmacion_incidencia`).

    Vive en la BD central: no altera `incidencias` del colegio. La clave natural
    es (apoderado, tenant, id_incidencia_colegio).
    """

    apoderado = models.ForeignKey(
        Apoderado,
        on_delete=models.CASCADE,
        db_column="apoderado_id",
        related_name="confirmaciones_incidencia",
    )
    tenant_id = models.TextField()
    id_incidencia_colegio = models.IntegerField()
    confirmada_en = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "asis_confirmacion_incidencia"
        verbose_name = "Confirmacion de incidencia"
        verbose_name_plural = "Confirmaciones de incidencia"
        constraints = [
            models.UniqueConstraint(
                fields=["apoderado", "tenant_id", "id_incidencia_colegio"],
                name="asis_uniq_conf_incidencia",
            ),
        ]
        indexes = [
            models.Index(
                fields=["apoderado", "tenant_id"],
                name="asis_idx_conf_apo_ten",
            ),
        ]

    def __str__(self) -> str:
        return f"confirmacion_incidencia:{self.pk}"


class IntentoLogin(models.Model):
    """Intento de login para el control de fuerza bruta (`asis_intento_login`).

    En `clave` va SIEMPRE el hash de (telefono, documento) que produce
    `apps.common.phone.hash_credencial`. Guardar el telefono o el
    `codigo_barras` en claro seria almacenar datos de un menor sin necesidad
    (Ley N.o 29733): esta tabla existe para contar, no para identificar.
    """

    clave = models.TextField(verbose_name="Hash de la credencial")
    ip = models.TextField(null=True, blank=True)
    exitoso = models.BooleanField(default=False)
    ocurrido_en = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "asis_intento_login"
        verbose_name = "Intento de login"
        verbose_name_plural = "Intentos de login"
        indexes = [
            models.Index(fields=["clave", "ocurrido_en"], name="asis_idx_intento_login_clave"),
        ]

    def __str__(self) -> str:
        return f"intento_login:{self.pk}"


class Auditoria(models.Model):
    """Rastro de acciones del canal (`asis_auditoria`).

    `detalle` es JSON tecnico: request_id, device_id, resultado. Nunca contenido
    de mensajes, nombres de estudiantes, telefonos ni `codigo_barras`.
    """

    apoderado = models.ForeignKey(
        Apoderado,
        on_delete=models.SET_NULL,
        db_column="apoderado_id",
        related_name="auditoria",
        null=True,
        blank=True,
    )
    actor = models.TextField(null=True, blank=True)
    accion = models.TextField()
    detalle = models.JSONField(null=True, blank=True)
    request_id = models.TextField(null=True, blank=True)
    ocurrido_en = models.DateTimeField(default=timezone.now)

    class Meta:
        db_table = "asis_auditoria"
        verbose_name = "Registro de auditoria"
        verbose_name_plural = "Auditoria"
        indexes = [
            models.Index(fields=["accion", "ocurrido_en"], name="asis_idx_auditoria_accion"),
        ]

    def __str__(self) -> str:
        return f"auditoria:{self.pk}"
