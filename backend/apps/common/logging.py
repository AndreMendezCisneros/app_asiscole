"""Logging estructurado en JSON del canal Asiscole.

Ley N.o 29733 (datos de menores): en los logs NUNCA se escriben `codigo_barras`,
telefonos, nombres de estudiantes, direcciones ni contenido de mensajes. Para
correlacionar una peticion se usa el `request_id` y los identificadores internos.

    logger.info("login", extra={"tenant": tenant_id, "resultado": "denegado"})

El formatter, ademas, redacta por si acaso cualquier campo `extra` cuyo nombre
suene a dato personal: es una red de seguridad, no una licencia para pasarlos.
"""

from __future__ import annotations

import json
import logging
from contextvars import ContextVar
from datetime import datetime, timezone

#: request_id de la peticion en curso; lo fija `RequestIdMiddleware`.
_request_id_actual: ContextVar[str] = ContextVar("asiscole_request_id", default="")


def set_request_id(request_id: str) -> object:
    """Fija el request_id del contexto actual y devuelve el token para restaurarlo."""
    return _request_id_actual.set(request_id or "")


def reset_request_id(token: object) -> None:
    """Restaura el request_id previo a partir del token de `set_request_id`."""
    try:
        _request_id_actual.reset(token)  # type: ignore[arg-type]
    except (ValueError, LookupError):
        # El contexto ya se cerro (por ejemplo en un hilo distinto): no es grave.
        _request_id_actual.set("")


def get_request_id() -> str:
    """Devuelve el request_id de la peticion en curso, o cadena vacia."""
    return _request_id_actual.get()


class RequestIdFilter(logging.Filter):
    """Inyecta `request_id` en cada registro para que el formatter lo emita."""

    def filter(self, record: logging.LogRecord) -> bool:
        if not getattr(record, "request_id", ""):
            record.request_id = get_request_id()
        return True


#: Atributos estandar de LogRecord: todo lo demas se considera "extra".
_ATRIBUTOS_ESTANDAR = frozenset(
    {
        "args",
        "asctime",
        "created",
        "exc_info",
        "exc_text",
        "filename",
        "funcName",
        "levelname",
        "levelno",
        "lineno",
        "message",
        "module",
        "msecs",
        "msg",
        "name",
        "pathname",
        "process",
        "processName",
        "relativeCreated",
        "stack_info",
        "taskName",
        "thread",
        "threadName",
        "request_id",
    }
)

#: Fragmentos de nombre que delatan un dato personal. Se redactan siempre.
_FRAGMENTOS_SENSIBLES = (
    "telefono",
    "phone",
    "celular",
    "codigo_barras",
    "dni",
    "documento",
    "nombre",
    "apellido",
    "direccion",
    "email",
    "correo",
    "mensaje",
    "contenido",
    "texto",
    "password",
    "token",
    "authorization",
)

REDACTADO = "[redactado]"


def _es_sensible(clave: str) -> bool:
    """Indica si el nombre de un campo sugiere que lleva un dato personal."""
    minuscula = clave.lower()
    return any(fragmento in minuscula for fragmento in _FRAGMENTOS_SENSIBLES)


def _serializable(valor: object) -> object:
    """Convierte un valor a algo que `json.dumps` acepte."""
    if valor is None or isinstance(valor, (str, int, float, bool)):
        return valor
    if isinstance(valor, dict):
        return {str(k): (REDACTADO if _es_sensible(str(k)) else _serializable(v)) for k, v in valor.items()}
    if isinstance(valor, (list, tuple, set)):
        return [_serializable(v) for v in valor]
    return str(valor)


class JsonFormatter(logging.Formatter):
    """Emite cada registro como una linea JSON.

    Campos fijos: `timestamp` (ISO-8601 UTC), `level`, `logger`, `message` y
    `request_id`. Los `extra` del llamante se anaden al mismo nivel, salvo los
    que parezcan datos personales, que salen como `[redactado]`.
    """

    def format(self, record: logging.LogRecord) -> str:
        carga: dict[str, object] = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "") or get_request_id(),
        }

        for clave, valor in record.__dict__.items():
            if clave in _ATRIBUTOS_ESTANDAR or clave.startswith("_") or clave in carga:
                continue
            carga[clave] = REDACTADO if _es_sensible(clave) else _serializable(valor)

        if record.exc_info:
            # Solo el tipo y el traceback: el texto de la excepcion podria
            # arrastrar valores de una consulta.
            carga["exc_type"] = getattr(record.exc_info[0], "__name__", "Exception")
            carga["traceback"] = self.formatException(record.exc_info)

        if record.stack_info:
            carga["stack"] = self.formatStack(record.stack_info)

        return json.dumps(carga, ensure_ascii=False, default=str)
