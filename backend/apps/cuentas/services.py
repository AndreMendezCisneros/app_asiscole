"""Logica de negocio de cuentas: login, sesion y traspaso de dispositivo.

Reglas que gobiernan todo este modulo:

* El documento del login es `estudiantes.codigo_barras` (ADR-01) y la
  coincidencia es exacta: es la unica barrera real mientras no haya OTP (ADR-07).
* Un fallo nunca revela si el dato malo fue el telefono o el documento: siempre
  `STUDENT_LINK_NOT_FOUND`.
* Sesion unica por cuenta (RNF-02, ADR-06). Un segundo dispositivo recibe 409 y
  puede pedir un traspaso; la sesion vigente NO se reemplaza. La garantia dura
  es el indice unico parcial de la BD, no una comprobacion en Python.
* Ni el telefono ni el `codigo_barras` aparecen en un log (Ley N.o 29733).
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

import bcrypt
from django.conf import settings
from django.db import IntegrityError, connections, transaction
from django.utils import timezone

from apps.common.errors import (
    AccountSuspended,
    SessionAlreadyActive,
    SessionExpired,
    StudentLinkNotFound,
    TransferAlreadyPending,
    TransferExpired,
    Unauthenticated,
    ValidationError,
)
from apps.common.phone import normalizar_e164
from apps.cuentas import notificaciones, rate_limit, tokens
from apps.cuentas.models import (
    CUENTA_ACTIVA,
    CUENTA_ELIMINADA,
    CUENTA_SUSPENDIDA,
    PREFIJO_IDENTIDAD_ADMIN,
    ROL_APODERADO,
    ROLES_ADMINISTRACION,
    SESION_ACTIVA,
    SESION_EXPIRADA,
    SESION_REVOCADA,
    SESION_TRANSFERIDA,
    TRANSFERENCIA_APROBADA,
    TRANSFERENCIA_EXPIRADA,
    TRANSFERENCIA_PENDIENTE,
    TRANSFERENCIA_RECHAZADA,
    Apoderado,
    PushToken,
    SesionActiva,
    TransferenciaSesion,
    identidad_administrador,
)
from apps.directorio import services as directorio
from apps.directorio.dto import VinculoDTO
from config.db_router import tenant_alias

logger = logging.getLogger("asiscole.cuentas")


# ---------------------------------------------------------------------------
# Resultados
# ---------------------------------------------------------------------------

@dataclass
class SesionEmitida:
    """Respuesta del contrato `SesionCreada`."""

    session_token: str
    session_expira_en: datetime
    data_token: str
    data_expira_en: datetime
    perfil: dict


@dataclass
class DataTokenEmitido:
    """Respuesta del contrato `DataToken`."""

    data_token: str
    data_expira_en: datetime


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

def enmascarar_telefono(valor: str) -> str:
    """Enmascara un telefono para mostrarlo en el perfil (`+51*****321`).

    Args:
        valor: Telefono en E.164 o identidad sintetica de administrador.

    Returns:
        El valor enmascarado; para un administrador devuelve un marcador fijo,
        porque su identidad no es un telefono.
    """
    if not valor:
        return ""
    if valor.startswith(PREFIJO_IDENTIDAD_ADMIN):
        return "administrador"
    if len(valor) <= 6:
        return "*" * len(valor)
    return f"{valor[:3]}{'*' * (len(valor) - 6)}{valor[-3:]}"


def construir_perfil(apoderado: Apoderado, estudiante_activo_id: int | None = None) -> dict:
    """Arma el objeto `Perfil` del contrato.

    Args:
        apoderado: Cuenta autenticada.
        estudiante_activo_id: Estudiante sobre el que trabaja la sesión. Si se
            omite, se usa el guardado en la cuenta.
    """
    if estudiante_activo_id is None:
        estudiante_activo_id = apoderado.estudiante_activo_id
    return {
        "alias": apoderado.nombre_alias,
        "telefono": enmascarar_telefono(apoderado.telefono),
        "estado": apoderado.estado,
        "motivo_suspension": apoderado.motivo_suspension,
        "estudiante_activo_id": estudiante_activo_id,
    }


def normalizar_telefono_o_fallar(telefono: str) -> str:
    """Normaliza el telefono del login a E.164.

    Raises:
        ValidationError: El valor no contiene un telefono valido. Es el unico
            caso en el que el canal responde 400 en el login; cualquier otro
            fallo de datos es 404 para no dar pistas.
    """
    normalizado = normalizar_e164(telefono or "")
    if not normalizado:
        raise ValidationError()
    return normalizado


def _guardar_push_token(
    apoderado: Apoderado, device_id: str, token: str | None, plataforma: str | None = None
) -> None:
    """Registra o actualiza el token de push del dispositivo."""
    if not token:
        return
    PushToken.objects.update_or_create(
        apoderado=apoderado,
        device_id=device_id,
        defaults={"token": token, "plataforma": plataforma, "activo": True},
    )
    from apps.mensajeria.tasks import reintentar_push_pendientes

    reintentar_push_pendientes(apoderado)


def _obtener_o_crear_apoderado(identidad: str, alias: str | None = None) -> Apoderado:
    """Busca la cuenta por su identidad y la crea si es el primer login.

    Raises:
        AccountSuspended: La cuenta esta suspendida (RF-J03: el login nuevo
            tambien se deniega).
        Unauthenticated: La cuenta fue eliminada (RF-I06).
    """
    apoderado, creado = Apoderado.objects.get_or_create(
        telefono=identidad,
        defaults={"nombre_alias": alias, "estado": CUENTA_ACTIVA},
    )

    if apoderado.estado == CUENTA_SUSPENDIDA:
        raise AccountSuspended()
    if apoderado.estado == CUENTA_ELIMINADA:
        raise Unauthenticated()

    if not creado and alias and not apoderado.nombre_alias:
        apoderado.nombre_alias = alias
        apoderado.save(update_fields=["nombre_alias", "actualizado_en"])

    return apoderado


def _sesion_activa_de(apoderado: Apoderado) -> SesionActiva | None:
    """Devuelve la sesion activa de la cuenta, cerrando antes la que ya vencio."""
    sesion = SesionActiva.objects.filter(apoderado=apoderado, estado=SESION_ACTIVA).first()
    if sesion is None:
        return None
    if sesion.expira_en <= timezone.now():
        # Libera el indice unico parcial: una sesion caducada no debe impedir
        # un login nuevo.
        SesionActiva.objects.filter(pk=sesion.pk, estado=SESION_ACTIVA).update(
            estado=SESION_EXPIRADA
        )
        return None
    return sesion


def _emitir_par_de_tokens(sesion: SesionActiva, role: str) -> tuple[str, datetime, str, datetime]:
    """Emite el `session_token` y el `data_token` de una sesion."""
    session_token, session_exp = tokens.emitir_session_token(
        sesion.apoderado_id, sesion.jti, sesion.device_id, role=role
    )
    data_token, data_exp = tokens.emitir_data_token(sesion.apoderado_id, sesion.jti, role=role)
    return session_token, session_exp, data_token, data_exp


def _rol_de(apoderado: Apoderado, claims: dict | None = None) -> str:
    """Devuelve el rol que va en los tokens de esa cuenta."""
    if claims and claims.get("role"):
        return str(claims["role"])
    return ROL_APODERADO


def resolver_sesion_por_token(session_token: str) -> SesionActiva:
    """Valida un `session_token` y devuelve su sesion viva.

    Args:
        session_token: JWT de sesion, sin el prefijo `Bearer`.

    Returns:
        La fila de `asis_sesion_activa` correspondiente.

    Raises:
        Unauthenticated: El token es invalido, vencio o no es de tipo sesion.
        SessionExpired: El token es valido pero la sesion fue revocada, vencio o
            se transfirio a otro dispositivo.
        AccountSuspended: La cuenta esta suspendida.
    """
    claims = tokens.decodificar(session_token, tokens.TIPO_SESION)

    try:
        sesion = SesionActiva.objects.select_related("apoderado").get(jti=claims["jti"])
    except (SesionActiva.DoesNotExist, ValueError, TypeError) as exc:
        raise SessionExpired() from exc

    if sesion.estado != SESION_ACTIVA:
        raise SessionExpired()
    if sesion.expira_en <= timezone.now():
        SesionActiva.objects.filter(pk=sesion.pk, estado=SESION_ACTIVA).update(
            estado=SESION_EXPIRADA
        )
        raise SessionExpired()

    if sesion.apoderado.estado == CUENTA_SUSPENDIDA:
        raise AccountSuspended()
    if sesion.apoderado.estado == CUENTA_ELIMINADA:
        raise Unauthenticated()

    return sesion


# ---------------------------------------------------------------------------
# Login del apoderado (RF-A01 a RF-A05)
# ---------------------------------------------------------------------------

def _validar_credencial(telefono_e164: str, documento: str, credencial: str, ip: str | None) -> VinculoDTO:
    """Resuelve el directorio y comprueba el documento del estudiante.

    Returns:
        El vinculo cuyo `codigo_barras` coincide exactamente con el documento.

    Raises:
        StudentLinkNotFound: No hay vinculo para ese telefono, o ninguno de sus
            estudiantes tiene ese documento. No se distingue cual fallo.
        UpstreamSchoolDbUnavailable: No se pudo verificar contra los colegios.
    """
    vinculos = directorio.resolver_vinculos(telefono_e164)
    if not vinculos:
        rate_limit.registrar_fallo_login(credencial, ip)
        logger.info("login_denegado", extra={"resultado": "sin_vinculos"})
        raise StudentLinkNotFound()

    vinculo = directorio.buscar_por_documento(vinculos, documento)
    if vinculo is None:
        rate_limit.registrar_fallo_login(credencial, ip)
        logger.info("login_denegado", extra={"resultado": "documento_no_coincide"})
        raise StudentLinkNotFound()

    return vinculo


def login(
    telefono: str,
    documento: str,
    device_id: str,
    *,
    modelo: str | None = None,
    sistema_operativo: str | None = None,
    push_token: str | None = None,
    plataforma: str | None = None,
    alias: str | None = None,
    ip: str | None = None,
) -> SesionEmitida:
    """Inicia sesion en el canal (RF-A01 a RF-A05).

    Args:
        telefono: Telefono del apoderado; se normaliza a E.164.
        documento: `estudiantes.codigo_barras` del estudiante.
        device_id: Identificador del dispositivo.
        modelo: Modelo del equipo, informativo.
        sistema_operativo: SO del equipo, informativo.
        push_token: Token de notificaciones, si el cliente ya lo tiene.
        plataforma: `android` o `ios`.
        alias: Nombre para mostrar (RF-A06).
        ip: IP de origen, para el control de fuerza bruta.

    Returns:
        La sesion creada con sus dos tokens y el perfil.

    Raises:
        ValidationError: El telefono o el `device_id` no son utilizables.
        AccountLocked: Bloqueo temporal por intentos fallidos.
        StudentLinkNotFound: No hay vinculo telefono-documento.
        AccountSuspended: La cuenta esta suspendida.
        SessionAlreadyActive: Ya hay sesion en OTRO dispositivo.
        UpstreamSchoolDbUnavailable: No se pudo verificar el vinculo.
    """
    if not (device_id or "").strip():
        raise ValidationError()

    # 1. Normalizacion.
    telefono_e164 = normalizar_telefono_o_fallar(telefono)
    documento_limpio = (documento or "").strip()
    if not documento_limpio:
        raise ValidationError()

    # 2. Limite de intentos y bloqueo (SRS 14.3).
    credencial = rate_limit.clave_credencial(telefono_e164, documento_limpio)
    rate_limit.verificar_login(credencial, ip)

    # 3 y 4. Directorio y coincidencia exacta del documento.
    vinculo = _validar_credencial(telefono_e164, documento_limpio, credencial, ip)

    # Se guarda aparte porque el aviso push al dispositivo activo tiene que
    # enviarse FUERA de la transaccion: el 409 la revierte, y un `on_commit`
    # sobre una transaccion que nunca se confirma no llegaria a ejecutarse.
    apoderado_en_conflicto: Apoderado | None = None

    try:
        with transaction.atomic():
            # 5. Cuenta.
            apoderado = _obtener_o_crear_apoderado(telefono_e164, alias)

            # 6. Politica de sesion unica.
            sesion_vigente = _sesion_activa_de(apoderado)
            if sesion_vigente is not None and sesion_vigente.device_id != device_id:
                # Otro equipo: se deniega, nunca se reemplaza (ADR-06).
                apoderado_en_conflicto = apoderado
                logger.info(
                    "login_denegado",
                    extra={"resultado": "sesion_activa", "apoderado_id": apoderado.pk},
                )
                raise SessionAlreadyActive()

            expira_en = timezone.now() + timedelta(days=settings.SESSION_TOKEN_DAYS)

            if sesion_vigente is not None:
                # Mismo equipo: reinstalar la app no puede exigir al
                # administrador. Se rota el jti para que los tokens viejos
                # dejen de servir.
                sesion_vigente.jti = uuid.uuid4()
                sesion_vigente.modelo = modelo or sesion_vigente.modelo
                sesion_vigente.sistema_operativo = (
                    sistema_operativo or sesion_vigente.sistema_operativo
                )
                sesion_vigente.expira_en = expira_en
                sesion_vigente.ultima_actividad_en = timezone.now()
                sesion_vigente.save(
                    update_fields=[
                        "jti",
                        "modelo",
                        "sistema_operativo",
                        "expira_en",
                        "ultima_actividad_en",
                    ]
                )
                sesion = sesion_vigente
            else:
                try:
                    sesion = SesionActiva.objects.create(
                        apoderado=apoderado,
                        device_id=device_id,
                        jti=uuid.uuid4(),
                        modelo=modelo,
                        sistema_operativo=sistema_operativo,
                        estado=SESION_ACTIVA,
                        expira_en=expira_en,
                    )
                except IntegrityError as exc:
                    # Carrera entre dos logins simultaneos: el indice unico
                    # parcial `asis_uniq_sesion_activa` deja pasar a uno solo.
                    # El perdedor recibe el mismo 409 que un segundo dispositivo.
                    apoderado_en_conflicto = apoderado
                    logger.info(
                        "login_denegado",
                        extra={"resultado": "carrera_sesion", "apoderado_id": apoderado.pk},
                    )
                    raise SessionAlreadyActive() from exc

            # 7. Push y tokens.
            _guardar_push_token(apoderado, device_id, push_token, plataforma)
            rate_limit.registrar_exito_login(credencial, ip)
    except SessionAlreadyActive:
        if apoderado_en_conflicto is not None:
            notificaciones.notificar_intento_acceso(apoderado_en_conflicto, device_id)
        raise

    session_token, session_exp, data_token, data_exp = _emitir_par_de_tokens(
        sesion, _rol_de(apoderado)
    )

    if (
        apoderado.estudiante_activo_id != vinculo.id_estudiante
        or apoderado.estudiante_activo_tenant != vinculo.tenant_id
    ):
        apoderado.estudiante_activo_id = vinculo.id_estudiante
        apoderado.estudiante_activo_tenant = vinculo.tenant_id
        apoderado.save(
            update_fields=["estudiante_activo_id", "estudiante_activo_tenant", "actualizado_en"]
        )

    logger.info(
        "login_ok",
        extra={
            "apoderado_id": apoderado.pk,
            "tenant": vinculo.tenant_id,
            "sesion_id": sesion.pk,
        },
    )

    return SesionEmitida(
        session_token=session_token,
        session_expira_en=session_exp,
        data_token=data_token,
        data_expira_en=data_exp,
        perfil=construir_perfil(apoderado, vinculo.id_estudiante),
    )


# ---------------------------------------------------------------------------
# Ciclo de vida de la sesion
# ---------------------------------------------------------------------------

def refresh_data(session_token: str) -> DataTokenEmitido:
    """Emite un `data_token` nuevo a partir del `session_token`.

    Es lo que hace transparente la caducidad del token corto: el cliente lo
    llama sin que el usuario se entere.

    Args:
        session_token: JWT de sesion en crudo.

    Returns:
        El token de datos nuevo y su expiracion.

    Raises:
        Unauthenticated: El token de sesion no vale.
        SessionExpired: La sesion fue revocada, vencio o se transfirio.
        AccountSuspended: La cuenta esta suspendida.
    """
    sesion = resolver_sesion_por_token(session_token)

    ahora = timezone.now()
    SesionActiva.objects.filter(pk=sesion.pk).update(ultima_actividad_en=ahora)

    data_token, data_exp = tokens.emitir_data_token(
        sesion.apoderado_id, sesion.jti, role=_rol_de(sesion.apoderado)
    )
    return DataTokenEmitido(data_token=data_token, data_expira_en=data_exp)


def _jitter_renovacion_segundos(apoderado_id: int) -> int:
    """Desplazamiento estable por cuenta para escalonar las renovaciones.

    RF-A07: si todas las sesiones se emitieron el mismo dia (por ejemplo el del
    despliegue), todas entrarian en la ventana de renovacion a la vez. Este
    jitter, derivado del id del apoderado, reparte esas renovaciones a lo largo
    de las ultimas horas de la ventana y es determinista: la misma cuenta
    siempre obtiene el mismo desplazamiento.
    """
    reparto_maximo = 12 * 3600
    return (int(apoderado_id) * 2654435761) % reparto_maximo


def renovar_sesion(session_token: str) -> SesionEmitida:
    """Renueva el `session_token` si esta dentro de la ventana (RF-A07).

    Fuera de la ventana no se rota nada: se devuelve el token vigente y un
    `data_token` nuevo, que es lo que el cliente necesita de todos modos.

    Args:
        session_token: JWT de sesion en crudo.

    Returns:
        La sesion, rotada o no.
    """
    sesion = resolver_sesion_por_token(session_token)
    apoderado = sesion.apoderado
    rol = _rol_de(apoderado)

    restante = sesion.expira_en - timezone.now()
    umbral = timedelta(days=settings.SESSION_RENEW_WINDOW_DAYS) - timedelta(
        seconds=_jitter_renovacion_segundos(apoderado.pk)
    )

    if restante <= umbral:
        # Se rota sobre la MISMA fila: la cuenta sigue teniendo una sola sesion
        # activa y el indice unico parcial no se toca.
        sesion.jti = uuid.uuid4()
        sesion.expira_en = timezone.now() + timedelta(days=settings.SESSION_TOKEN_DAYS)
        sesion.ultima_actividad_en = timezone.now()
        sesion.save(update_fields=["jti", "expira_en", "ultima_actividad_en"])
        logger.info("sesion_renovada", extra={"apoderado_id": apoderado.pk})
        session_token_nuevo, session_exp, data_token, data_exp = _emitir_par_de_tokens(sesion, rol)
    else:
        SesionActiva.objects.filter(pk=sesion.pk).update(ultima_actividad_en=timezone.now())
        session_token_nuevo = session_token
        session_exp = sesion.expira_en
        data_token, data_exp = tokens.emitir_data_token(sesion.apoderado_id, sesion.jti, role=rol)

    return SesionEmitida(
        session_token=session_token_nuevo,
        session_expira_en=session_exp,
        data_token=data_token,
        data_expira_en=data_exp,
        perfil=construir_perfil(apoderado),
    )


def logout(sesion: SesionActiva) -> None:
    """Cierra la sesion y desactiva el push del dispositivo (CU-07)."""
    with transaction.atomic():
        SesionActiva.objects.filter(pk=sesion.pk, estado=SESION_ACTIVA).update(
            estado=SESION_REVOCADA, ultima_actividad_en=timezone.now()
        )
        PushToken.objects.filter(
            apoderado_id=sesion.apoderado_id, device_id=sesion.device_id
        ).update(activo=False)
    logger.info("logout", extra={"apoderado_id": sesion.apoderado_id, "sesion_id": sesion.pk})


# ---------------------------------------------------------------------------
# Traspaso de dispositivo (RF-A09 / CU-09)
# ---------------------------------------------------------------------------

def solicitar_transferencia(
    telefono: str, documento: str, device_id: str, *, ip: str | None = None
) -> TransferenciaSesion:
    """Pide el traspaso de la sesion al dispositivo nuevo (RF-A09).

    El equipo solicitante se identifica con la misma credencial del login: sin
    esa comprobacion cualquiera podria molestar al dispositivo activo.

    Args:
        telefono: Telefono del apoderado.
        documento: Documento del estudiante.
        device_id: Dispositivo que quiere quedarse con la sesion.
        ip: IP de origen.

    Returns:
        La solicitud creada, en estado `pending`.

    Raises:
        StudentLinkNotFound: La credencial no corresponde a ningun vinculo.
        SessionExpired: No hay ninguna sesion activa que trasladar; el
            dispositivo deberia iniciar sesion normalmente.
        TransferAlreadyPending: Ya hay una solicitud en curso.
        TooManyRequests: Se supero `TRANSFER_MAX_PER_HOUR`.
    """
    if not (device_id or "").strip():
        raise ValidationError()

    telefono_e164 = normalizar_telefono_o_fallar(telefono)
    documento_limpio = (documento or "").strip()
    credencial = rate_limit.clave_credencial(telefono_e164, documento_limpio)
    rate_limit.verificar_login(credencial, ip)
    _validar_credencial(telefono_e164, documento_limpio, credencial, ip)

    try:
        apoderado = Apoderado.objects.get(telefono=telefono_e164)
    except Apoderado.DoesNotExist as exc:
        # Hay vinculo pero nunca hubo login: no hay nada que trasladar.
        raise StudentLinkNotFound() from exc

    if apoderado.estado == CUENTA_SUSPENDIDA:
        raise AccountSuspended()

    sesion_vigente = _sesion_activa_de(apoderado)
    if sesion_vigente is None:
        raise SessionExpired("No hay una sesión activa que trasladar. Inicia sesión normalmente.")
    if sesion_vigente.device_id == device_id:
        # Es el mismo equipo: no necesita traspaso, le basta con volver a entrar.
        raise SessionExpired("Este dispositivo ya puede iniciar sesión.")

    rate_limit.verificar_transferencias(apoderado.pk)

    pendiente = TransferenciaSesion.objects.filter(
        apoderado=apoderado, estado=TRANSFERENCIA_PENDIENTE
    ).first()
    if pendiente is not None:
        if pendiente.vencida:
            pendiente.estado = TRANSFERENCIA_EXPIRADA
            pendiente.save(update_fields=["estado"])
        else:
            raise TransferAlreadyPending()

    try:
        with transaction.atomic():
            transferencia = TransferenciaSesion.objects.create(
                apoderado=apoderado,
                from_device_id=sesion_vigente.device_id,
                to_device_id=device_id,
                estado=TRANSFERENCIA_PENDIENTE,
                expira_en=timezone.now()
                + timedelta(minutes=settings.TRANSFER_REQUEST_TTL_MINUTES),
            )
    except IntegrityError as exc:
        # Carrera contra el indice unico parcial de solicitudes pendientes.
        raise TransferAlreadyPending() from exc

    rate_limit.registrar_transferencia(apoderado.pk)
    notificaciones.notificar_solicitud_transferencia(apoderado, transferencia)
    logger.info(
        "transferencia_solicitada",
        extra={"apoderado_id": apoderado.pk, "transferencia_id": transferencia.pk},
    )
    return transferencia


def _transferencia_vigente(id_transferencia: int) -> TransferenciaSesion:
    """Carga una solicitud y la marca expirada si se le paso el plazo.

    Raises:
        TransferExpired: La solicitud no existe, ya se resolvio o vencio.
    """
    try:
        transferencia = TransferenciaSesion.objects.select_related("apoderado").get(
            pk=id_transferencia
        )
    except (TransferenciaSesion.DoesNotExist, ValueError, TypeError) as exc:
        raise TransferExpired() from exc

    if transferencia.estado == TRANSFERENCIA_PENDIENTE and transferencia.vencida:
        transferencia.estado = TRANSFERENCIA_EXPIRADA
        transferencia.save(update_fields=["estado"])

    if transferencia.estado != TRANSFERENCIA_PENDIENTE:
        raise TransferExpired()

    return transferencia


def aprobar_transferencia(id_transferencia: int, sesion_actual: SesionActiva) -> TransferenciaSesion:
    """Aprueba el traspaso desde el dispositivo que tiene la sesion (RF-A09).

    Cierra la sesion actual. El dispositivo nuevo obtiene sus tokens cuando
    reintenta el login, porque ya no habra sesion activa que se lo impida.

    Raises:
        Unauthenticated: Quien aprueba no es el dueno de la solicitud.
        TransferExpired: La solicitud vencio o ya se resolvio.
    """
    transferencia = _transferencia_vigente(id_transferencia)

    if transferencia.apoderado_id != sesion_actual.apoderado_id:
        # No se confirma siquiera que la solicitud exista.
        raise Unauthenticated()

    with transaction.atomic():
        SesionActiva.objects.filter(pk=sesion_actual.pk, estado=SESION_ACTIVA).update(
            estado=SESION_TRANSFERIDA, ultima_actividad_en=timezone.now()
        )
        transferencia.estado = TRANSFERENCIA_APROBADA
        transferencia.save(update_fields=["estado"])

    logger.info(
        "transferencia_aprobada",
        extra={
            "apoderado_id": transferencia.apoderado_id,
            "transferencia_id": transferencia.pk,
        },
    )
    return transferencia


def rechazar_transferencia(
    id_transferencia: int, sesion_actual: SesionActiva
) -> TransferenciaSesion:
    """Rechaza el traspaso. La sesion del dispositivo actual sigue intacta."""
    transferencia = _transferencia_vigente(id_transferencia)

    if transferencia.apoderado_id != sesion_actual.apoderado_id:
        raise Unauthenticated()

    transferencia.estado = TRANSFERENCIA_RECHAZADA
    transferencia.save(update_fields=["estado"])
    logger.info(
        "transferencia_rechazada",
        extra={
            "apoderado_id": transferencia.apoderado_id,
            "transferencia_id": transferencia.pk,
        },
    )
    return transferencia


def consultar_transferencia(id_transferencia: int) -> TransferenciaSesion:
    """Consulta el estado de una solicitud desde el dispositivo solicitante.

    Raises:
        TransferExpired: La solicitud vencio (y se marca `expired` al pasar).
    """
    try:
        transferencia = TransferenciaSesion.objects.get(pk=id_transferencia)
    except (TransferenciaSesion.DoesNotExist, ValueError, TypeError) as exc:
        raise TransferExpired() from exc

    if transferencia.estado == TRANSFERENCIA_PENDIENTE and transferencia.vencida:
        transferencia.estado = TRANSFERENCIA_EXPIRADA
        transferencia.save(update_fields=["estado"])
        raise TransferExpired()

    if transferencia.estado == TRANSFERENCIA_EXPIRADA:
        raise TransferExpired()

    return transferencia


# ---------------------------------------------------------------------------
# Login del administrador (RF-B01)
# ---------------------------------------------------------------------------

#: `usuarios.password_hash` es bcrypt generado con `extensions.crypt`. El modelo
#: espejo de `academico` omite la columna a proposito, asi que se lee con SQL.
_SQL_USUARIO_ADMIN = """
    SELECT id_usuario, password_hash, rol::text, activo, nombre_completo
      FROM public.usuarios
     WHERE username = %s
"""


def _verificar_bcrypt(password: str, hash_guardado: str) -> bool:
    """Compara una contrasena contra el hash bcrypt del colegio."""
    if not hash_guardado or not hash_guardado.startswith("$2"):
        return False
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hash_guardado.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def login_administrador(
    usuario: str,
    password: str,
    device_id: str,
    tenant_id: str,
    *,
    ip: str | None = None,
) -> SesionEmitida:
    """Inicia sesion un usuario de administracion del colegio (RF-B01).

    Valida usuario y contrasena contra la tabla `usuarios` del colegio indicado
    y aplica la misma politica de sesion unica que el apoderado.

    Args:
        usuario: `usuarios.username`.
        password: Contrasena en claro; se compara con bcrypt.
        device_id: Dispositivo.
        tenant_id: Colegio. Aqui SI viene del cliente, porque es parte de la
            credencial: se comprueba que este configurado y la sesion queda
            atada a el; ninguna consulta posterior lo toma del request.
        ip: IP de origen.

    Returns:
        La sesion creada con sus dos tokens.

    Raises:
        ValidationError: Faltan campos.
        Unauthenticated: Colegio desconocido, credencial incorrecta, cuenta
            inactiva o rol sin permiso. No se distingue el motivo.
        AccountLocked: Bloqueo temporal por intentos fallidos.
        SessionAlreadyActive: Ya hay sesion en otro dispositivo.
    """
    if not (usuario or "").strip() or not password or not (device_id or "").strip():
        raise ValidationError()

    tenant = (tenant_id or "").strip()
    if tenant not in settings.SCHOOL_TENANTS:
        raise Unauthenticated()

    credencial = rate_limit.clave_credencial(f"{PREFIJO_IDENTIDAD_ADMIN}{tenant}:{usuario}", "")
    rate_limit.verificar_login(credencial, ip)

    with connections[tenant_alias(tenant)].cursor() as cursor:
        cursor.execute(_SQL_USUARIO_ADMIN, [usuario.strip()])
        fila = cursor.fetchone()

    if fila is None:
        rate_limit.registrar_fallo_login(credencial, ip)
        raise Unauthenticated()

    id_usuario, password_hash, rol, activo, nombre_completo = fila

    if not activo or rol not in ROLES_ADMINISTRACION or not _verificar_bcrypt(password, password_hash):
        rate_limit.registrar_fallo_login(credencial, ip)
        logger.info("login_admin_denegado", extra={"tenant": tenant})
        raise Unauthenticated()

    identidad = identidad_administrador(tenant, int(id_usuario))

    with transaction.atomic():
        apoderado = _obtener_o_crear_apoderado(identidad, nombre_completo)

        sesion_vigente = _sesion_activa_de(apoderado)
        if sesion_vigente is not None and sesion_vigente.device_id != device_id:
            raise SessionAlreadyActive()

        expira_en = timezone.now() + timedelta(days=settings.SESSION_TOKEN_DAYS)
        if sesion_vigente is not None:
            sesion_vigente.jti = uuid.uuid4()
            sesion_vigente.expira_en = expira_en
            sesion_vigente.ultima_actividad_en = timezone.now()
            sesion_vigente.save(update_fields=["jti", "expira_en", "ultima_actividad_en"])
            sesion = sesion_vigente
        else:
            try:
                sesion = SesionActiva.objects.create(
                    apoderado=apoderado,
                    device_id=device_id,
                    jti=uuid.uuid4(),
                    estado=SESION_ACTIVA,
                    expira_en=expira_en,
                )
            except IntegrityError as exc:
                raise SessionAlreadyActive() from exc

        rate_limit.registrar_exito_login(credencial, ip)

    session_token, session_exp, data_token, data_exp = _emitir_par_de_tokens(sesion, rol)
    logger.info("login_admin_ok", extra={"tenant": tenant, "apoderado_id": apoderado.pk})

    return SesionEmitida(
        session_token=session_token,
        session_expira_en=session_exp,
        data_token=data_token,
        data_expira_en=data_exp,
        perfil=construir_perfil(apoderado),
    )
