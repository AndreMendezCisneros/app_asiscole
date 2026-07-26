"""Los dos tokens JWT del canal (SRS 14.1, seccion "Modelo de tokens").

* `session_token`: 10 dias (`SESSION_TOKEN_DAYS`). Es el que prueba el login y
  SOLO sirve en `/auth/*`. Su `jti` es el de la fila de `asis_sesion_activa`,
  asi que revocar la sesion lo invalida sin necesidad de una lista negra.
* `data_token`: minutos (`DATA_TOKEN_MINUTES`). Es el que llevan todos los
  endpoints de negocio. Lleva en `sid` el `jti` de la sesion que lo respalda.

La separacion solo sirve de algo si se comprueba: `decodificar` exige que el
claim `typ` coincida con el tipo esperado, de modo que un `session_token` no
abre un endpoint de negocio ni un `data_token` renueva la sesion.

Firma HS256 con `DJANGO_SECRET_KEY`.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone as zona_utc

import jwt
from django.conf import settings

from apps.common.errors import Unauthenticated
from apps.cuentas.models import ROL_APODERADO

#: Valores del claim `typ`.
TIPO_SESION = "session"
TIPO_DATOS = "data"

#: Alcance del `data_token`. Hoy solo hay uno; queda explicito para que anadir
#: otro (por ejemplo escritura) sea un cambio de contrato consciente.
SCOPE_LECTURA_ESTUDIANTE = "student_read"

ALGORITMO = "HS256"


def _ahora() -> datetime:
    """Instante actual en UTC, truncado al segundo (los claims JWT son enteros)."""
    return datetime.now(tz=zona_utc.utc).replace(microsecond=0)


def _clave() -> str:
    """Devuelve la clave de firma."""
    return settings.SECRET_KEY


def emitir_session_token(
    apoderado_id: int,
    jti: uuid.UUID | str,
    device_id: str,
    *,
    role: str = ROL_APODERADO,
    emitido_en: datetime | None = None,
) -> tuple[str, datetime]:
    """Emite el token de sesion.

    Args:
        apoderado_id: PK del apoderado, va en `sub`.
        jti: Identificador de la sesion; el mismo de `asis_sesion_activa.jti`.
        device_id: Dispositivo al que queda atada la sesion.
        role: Rol del titular (`apoderado`, `Admin`, `Director`, `Supervisor`).
        emitido_en: Permite fijar el `iat` (util en pruebas y al renovar).

    Returns:
        La tupla `(token, expira_en)`, con la expiracion en UTC.
    """
    iat = emitido_en or _ahora()
    exp = iat + timedelta(days=settings.SESSION_TOKEN_DAYS)
    carga = {
        "sub": str(apoderado_id),
        "typ": TIPO_SESION,
        "jti": str(jti),
        "device_id": device_id,
        "role": role,
        "iat": int(iat.timestamp()),
        "exp": int(exp.timestamp()),
    }
    return jwt.encode(carga, _clave(), algorithm=ALGORITMO), exp


def emitir_data_token(
    apoderado_id: int,
    sid: uuid.UUID | str,
    *,
    role: str = ROL_APODERADO,
    scope: str = SCOPE_LECTURA_ESTUDIANTE,
    emitido_en: datetime | None = None,
) -> tuple[str, datetime]:
    """Emite el token de datos, de vida corta.

    Args:
        apoderado_id: PK del apoderado, va en `sub`.
        sid: `jti` de la sesion que respalda al token.
        role: Rol del titular.
        scope: Alcance concedido.
        emitido_en: Permite fijar el `iat`.

    Returns:
        La tupla `(token, expira_en)`, con la expiracion en UTC.
    """
    iat = emitido_en or _ahora()
    exp = iat + timedelta(minutes=settings.DATA_TOKEN_MINUTES)
    carga = {
        "sub": str(apoderado_id),
        "typ": TIPO_DATOS,
        "sid": str(sid),
        "role": role,
        "scope": scope,
        "iat": int(iat.timestamp()),
        "exp": int(exp.timestamp()),
    }
    return jwt.encode(carga, _clave(), algorithm=ALGORITMO), exp


def decodificar(token: str, tipo_esperado: str) -> dict:
    """Valida la firma, la vigencia y el tipo de un token.

    Args:
        token: JWT en crudo, sin el prefijo `Bearer`.
        tipo_esperado: `TIPO_SESION` o `TIPO_DATOS`.

    Returns:
        Los claims del token.

    Raises:
        Unauthenticated: Firma invalida, token vencido, mal formado o de un tipo
            distinto al esperado. El motivo exacto no se revela al cliente ni se
            escribe en el log.
    """
    if not token:
        raise Unauthenticated()

    try:
        claims = jwt.decode(
            token,
            _clave(),
            algorithms=[ALGORITMO],
            options={"require": ["exp", "iat", "sub", "typ"]},
        )
    except jwt.PyJWTError as exc:
        raise Unauthenticated() from exc

    if claims.get("typ") != tipo_esperado:
        # Un token valido pero del tipo equivocado es tan invalido como uno roto:
        # es justo la confusion que separa /auth/* de los endpoints de negocio.
        raise Unauthenticated()

    identificador = claims.get("jti") if tipo_esperado == TIPO_SESION else claims.get("sid")
    if not identificador:
        raise Unauthenticated()

    return claims


def identificador_de_sesion(claims: dict) -> str:
    """Devuelve el `jti` de la sesion, venga de un token de sesion o de datos."""
    return str(claims.get("jti") or claims.get("sid") or "")


def token_del_encabezado(encabezado: str | None) -> str:
    """Extrae el JWT de un encabezado `Authorization: Bearer <token>`.

    Raises:
        Unauthenticated: Si falta el encabezado o no usa el esquema Bearer.
    """
    crudo = (encabezado or "").strip()
    if not crudo:
        raise Unauthenticated()
    partes = crudo.split()
    if len(partes) != 2 or partes[0].lower() != "bearer":
        raise Unauthenticated()
    return partes[1]
