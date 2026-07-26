"""Catalogo de errores del canal Asiscole (SRS 14.2).

Toda respuesta de error del API sale de aqui. Ninguna vista devuelve un `detail`
suelto: cada error viaja con su codigo estable, que es lo que consume la app.

Los mensajes estan redactados en espanol de Peru y son aptos para mostrarse tal
cual al apoderado. Nunca contienen datos personales ni pistas que permitan
enumerar telefonos o documentos de estudiantes.
"""

from __future__ import annotations

from rest_framework.exceptions import APIException


class AsiscoleError(APIException):
    """Error base del canal.

    Attributes:
        status_code: Codigo HTTP con el que se responde.
        code: Codigo estable del catalogo (lo consume el cliente).
        default_message: Texto por defecto, ya apto para el usuario final.
    """

    status_code = 500
    code = "INTERNAL_ERROR"
    default_message = "Ocurrió un error inesperado. Vuelve a intentarlo en unos minutos."

    def __init__(self, message: str | None = None, *, contexto: dict | None = None):
        """Crea el error.

        Args:
            message: Texto alternativo para el usuario. Si se omite se usa
                `default_message`. Nunca debe incluir datos personales.
            contexto: Metadatos internos para el log (identificadores, tenant).
                No se serializan en la respuesta HTTP.
        """
        self.message = message or self.default_message
        self.contexto = contexto or {}
        super().__init__(detail=self.message, code=self.code)

    def __str__(self) -> str:
        return f"{self.code}: {self.message}"


class ValidationError(AsiscoleError):
    """400 — La petición no cumple el contrato (campos faltantes o mal formados)."""

    status_code = 400
    code = "VALIDATION_ERROR"
    default_message = "Los datos enviados no son válidos. Revísalos e inténtalo otra vez."


class Unauthenticated(AsiscoleError):
    """401 — Falta el token, está mal formado o la firma no valida."""

    status_code = 401
    code = "UNAUTHENTICATED"
    default_message = "Debes iniciar sesión para continuar."


class AccountSuspended(AsiscoleError):
    """403 — La cuenta del apoderado fue suspendida por el colegio."""

    status_code = 403
    code = "ACCOUNT_SUSPENDED"
    default_message = "Tu cuenta está suspendida. Comunícate con el colegio."


class RoleNotAllowed(AsiscoleError):
    """403 — El usuario existe en el colegio pero no tiene rol de apoderado."""

    status_code = 403
    code = "ROLE_NOT_ALLOWED"
    default_message = "Esta aplicación es solo para apoderados."


class StudentLinkNotFound(AsiscoleError):
    """404 — No hay vínculo apoderado-estudiante para los datos recibidos.

    El mensaje es deliberadamente ambiguo: no revela si falló el teléfono o el
    documento, para no facilitar la enumeración de datos de menores.
    """

    status_code = 404
    code = "STUDENT_LINK_NOT_FOUND"
    default_message = (
        "No encontramos un estudiante registrado con esos datos. "
        "Verifica la información con el colegio."
    )


class SessionAlreadyActive(AsiscoleError):
    """409 — Ya hay una sesión activa en otro dispositivo.

    El segundo login se deniega; no reemplaza a la sesión existente. El apoderado
    debe pedir la transferencia de dispositivo.
    """

    status_code = 409
    code = "SESSION_ALREADY_ACTIVE"
    default_message = (
        "Ya existe una sesión activa en otro dispositivo. "
        "Solicita el traslado de sesión para continuar aquí."
    )


class TransferAlreadyPending(AsiscoleError):
    """409 — Ya hay una solicitud de traslado de dispositivo en curso."""

    status_code = 409
    code = "TRANSFER_ALREADY_PENDING"
    default_message = "Ya tienes una solicitud de traslado pendiente. Espera a que se resuelva."


class SessionExpired(AsiscoleError):
    """410 — La sesión venció o fue revocada; hay que volver a iniciar sesión."""

    status_code = 410
    code = "SESSION_EXPIRED"
    default_message = "Tu sesión expiró. Inicia sesión nuevamente."


class TransferExpired(AsiscoleError):
    """410 — La solicitud de traslado superó su tiempo de vida."""

    status_code = 410
    code = "TRANSFER_EXPIRED"
    default_message = "La solicitud de traslado expiró. Genera una nueva."


class AccountLocked(AsiscoleError):
    """423 — Cuenta bloqueada temporalmente por intentos fallidos de login."""

    status_code = 423
    code = "ACCOUNT_LOCKED"
    default_message = (
        "Bloqueamos el acceso temporalmente por varios intentos fallidos. "
        "Inténtalo más tarde."
    )


class TooManyRequests(AsiscoleError):
    """429 — Se superó el límite de peticiones permitido."""

    status_code = 429
    code = "TOO_MANY_REQUESTS"
    default_message = "Hiciste demasiadas solicitudes seguidas. Espera un momento e inténtalo otra vez."


class UpstreamSchoolDbUnavailable(AsiscoleError):
    """503 — La base de datos del colegio no responde o el circuito está abierto."""

    status_code = 503
    code = "UPSTREAM_SCHOOL_DB_UNAVAILABLE"
    default_message = (
        "No pudimos conectarnos con el sistema del colegio. "
        "Vuelve a intentarlo en unos minutos."
    )


#: Codigos validos del catalogo, para validaciones y pruebas de contrato.
CODIGOS_DE_ERROR: dict[str, type[AsiscoleError]] = {
    clase.code: clase
    for clase in (
        ValidationError,
        Unauthenticated,
        AccountSuspended,
        RoleNotAllowed,
        StudentLinkNotFound,
        SessionAlreadyActive,
        TransferAlreadyPending,
        SessionExpired,
        TransferExpired,
        AccountLocked,
        TooManyRequests,
        UpstreamSchoolDbUnavailable,
    )
}

#: Codigo generico para fallos no previstos; no forma parte del contrato publico.
CODIGO_INTERNO = AsiscoleError.code
