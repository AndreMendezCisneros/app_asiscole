"""Configuracion de Django para el canal Asiscole.

Todo se lee de variables de entorno con los nombres exactos de `.env.example`.
El backend habla con dos clases de base de datos:

* La BD central del canal (`default`): cuentas, sesiones, directorio y mensajes.
* Una BD por colegio (alias `colegio_<tenant_id>`), de SOLO LECTURA, declaradas en
  la variable JSON `SCHOOL_DATABASES`.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from celery.schedules import crontab
from dotenv import load_dotenv

# backend/
BASE_DIR = Path(__file__).resolve().parent.parent

# El .env vive en la raiz del monorepo (junto al docker-compose). En contenedor
# las variables ya vienen inyectadas por `env_file`, y load_dotenv no las pisa.
# interpolate=False: passwords con `$` (comunes) no se corrompen.
load_dotenv(BASE_DIR.parent / ".env", interpolate=False)
load_dotenv(BASE_DIR / ".env", interpolate=False)


# ---------------------------------------------------------------------------
# Ayudas de lectura del entorno
# ---------------------------------------------------------------------------

def env_str(clave: str, defecto: str = "") -> str:
    """Devuelve una variable de entorno como texto, sin espacios sobrantes."""
    valor = os.environ.get(clave)
    return defecto if valor is None else valor.strip()


def env_bool(clave: str, defecto: bool = False) -> bool:
    """Interpreta '1', 'true', 'yes', 'on' (sin distinguir mayusculas) como True."""
    valor = os.environ.get(clave)
    if valor is None or valor.strip() == "":
        return defecto
    return valor.strip().lower() in {"1", "true", "yes", "on", "si"}


def env_int(clave: str, defecto: int) -> int:
    """Devuelve una variable de entorno como entero; si no es valida usa el defecto."""
    valor = os.environ.get(clave)
    if valor is None or valor.strip() == "":
        return defecto
    try:
        return int(valor.strip())
    except ValueError:
        return defecto


def env_list(clave: str, defecto: str = "") -> list[str]:
    """Parte una variable separada por comas en una lista sin elementos vacios."""
    crudo = env_str(clave, defecto)
    return [parte.strip() for parte in crudo.split(",") if parte.strip()]


# ---------------------------------------------------------------------------
# Nucleo de Django
# ---------------------------------------------------------------------------

SECRET_KEY = env_str("DJANGO_SECRET_KEY", "cambiar-en-produccion")
DEBUG = env_bool("DJANGO_DEBUG", False)
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
# En desarrollo local el celular físico llama por la IP de la LAN; sin esto
# Django responde 400 DisallowedHost y la app solo ve timeout/error.
if DEBUG and "*" not in ALLOWED_HOSTS:
    ALLOWED_HOSTS = list({*ALLOWED_HOSTS, "*", "10.0.2.2"})

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.staticfiles",
    # Terceros
    "rest_framework",
    "drf_spectacular",
    # Apps del canal
    "apps.common",
    "apps.directorio",
    "apps.cuentas",
    "apps.mensajeria",
    "apps.ingesta",
    "apps.academico",
    "apps.administracion",
]

# No se instalan django.contrib.auth ni admin: el canal tiene su propio modelo de
# apoderado y de sesion (10 dias + device_id), sin usuarios de Django.

MIDDLEWARE = [
    "apps.common.middleware.RequestIdMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
]

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {"context_processors": []},
    },
]


# ---------------------------------------------------------------------------
# Bases de datos
# ---------------------------------------------------------------------------

SCHOOL_DB_TIMEOUT_SECONDS = env_int("SCHOOL_DB_TIMEOUT_SECONDS", 2)

#: Motor de la BD central en produccion. Se guarda aparte porque bajo pytest la
#: conexion `default` se sustituye (ver mas abajo) y las pruebas de configuracion
#: siguen necesitando comprobar cual es el motor real.
CENTRAL_DB_ENGINE = "django.db.backends.postgresql"

#: `sslmode` de libpq. En Supabase debe ser `require` (o `verify-full`).
#: En Postgres local de Docker se deja vacio.
_CENTRAL_SSLMODE = env_str("CENTRAL_DB_SSLMODE", "")
_CENTRAL_OPTIONS: dict = {"connect_timeout": env_int("CENTRAL_DB_TIMEOUT_SECONDS", 5)}
if _CENTRAL_SSLMODE:
    _CENTRAL_OPTIONS["sslmode"] = _CENTRAL_SSLMODE

DATABASES = {
    "default": {
        "ENGINE": CENTRAL_DB_ENGINE,
        "NAME": env_str("CENTRAL_DB_NAME", "postgres"),
        "USER": env_str("CENTRAL_DB_USER", "postgres"),
        "PASSWORD": env_str("CENTRAL_DB_PASSWORD", ""),
        "HOST": env_str("CENTRAL_DB_HOST", "localhost"),
        "PORT": env_str("CENTRAL_DB_PORT", "5432"),
        "CONN_MAX_AGE": env_int("CENTRAL_DB_CONN_MAX_AGE", 60),
        "OPTIONS": _CENTRAL_OPTIONS,
        "TIME_ZONE": "America/Lima",
    }
}


def _cargar_colegios(crudo: str) -> list[dict]:
    """Parsea `SCHOOL_DATABASES`; ante un JSON invalido arranca sin colegios."""
    if not crudo:
        return []
    try:
        datos = json.loads(crudo)
    except json.JSONDecodeError:
        # No se propaga la excepcion para que el backend arranque igual: sin
        # colegios el canal responde UPSTREAM_SCHOOL_DB_UNAVAILABLE, que es
        # preferible a un contenedor que no levanta.
        return []
    return [entrada for entrada in datos if isinstance(entrada, dict)] if isinstance(datos, list) else []


#: Metadatos de los colegios (tenant_id -> nombre visible), sin credenciales.
SCHOOL_TENANTS: dict[str, str] = {}

for _colegio in _cargar_colegios(env_str("SCHOOL_DATABASES", "[]")):
    _tenant_id = str(_colegio.get("tenant_id", "")).strip()
    if not _tenant_id:
        continue
    _alias = f"colegio_{_tenant_id}"
    _school_options: dict = {"connect_timeout": SCHOOL_DB_TIMEOUT_SECONDS}
    _school_ssl = str(_colegio.get("sslmode", "")).strip()
    if _school_ssl:
        _school_options["sslmode"] = _school_ssl
    DATABASES[_alias] = {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": _colegio.get("name", "postgres"),
        "USER": _colegio.get("user", ""),
        "PASSWORD": _colegio.get("password", ""),
        "HOST": _colegio.get("host", ""),
        "PORT": str(_colegio.get("port", 5432)),
        # Timeout corto: un colegio caido no puede colgar al resto (SRS 7.8).
        "OPTIONS": _school_options,
        "TIME_ZONE": "America/Lima",
        "CONN_MAX_AGE": env_int("SCHOOL_DB_CONN_MAX_AGE", 60),
        # Las BDs de colegio jamas se migran ni se usan como BD de pruebas.
        "TEST": {"MIRROR": "default"},
    }
    SCHOOL_TENANTS[_tenant_id] = str(_colegio.get("nombre", _tenant_id))

#: True cuando el proceso lo arranco pytest.
EJECUTANDO_PRUEBAS = "pytest" in sys.modules

if EJECUTANDO_PRUEBAS and not env_bool("TEST_USE_POSTGRES", False):
    # La suite corre sobre SQLite en memoria para que no dependa de que haya un
    # PostgreSQL levantado con las credenciales del `.env`. SQLite soporta
    # indices unicos parciales, que es justo lo que necesita la garantia de
    # sesion unica (`asis_uniq_sesion_activa`), asi que esa regla se prueba de
    # verdad y no de mentira. Con `TEST_USE_POSTGRES=1` la suite vuelve a
    # ejecutarse contra PostgreSQL.
    DATABASES["default"] = {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}

DATABASE_ROUTERS = ["config.db_router.TenantRouter"]

# `academico` es un espejo de solo lectura del esquema del colegio: declararla
# sin migraciones evita que un `makemigrations` distraido genere historial para
# tablas que el canal no posee. El router bloquea ademas cualquier intento.
MIGRATION_MODULES = {"academico": None}


# ---------------------------------------------------------------------------
# Cache (Redis en prod; LocMem opcional en local sin Docker)
# ---------------------------------------------------------------------------

REDIS_URL = env_str("REDIS_URL", "redis://localhost:6379/0")

USE_LOCMEM_CACHE = env_bool("USE_LOCMEM_CACHE", False)
# Sin Celery/Redis: el runserver vacía asis_outbox en un hilo (misma lógica
# que el beat). En producción debe quedar False y usarse worker+beat.
POLL_OUTBOX_INLINE = env_bool("POLL_OUTBOX_INLINE", USE_LOCMEM_CACHE)
POLL_OUTBOX_INLINE_SECONDS = max(5, env_int("POLL_OUTBOX_INLINE_SECONDS", 15))

if USE_LOCMEM_CACHE:
    # Desarrollo sin Redis/Docker: rate-limit, directorio y push idempotencia
    # viven en memoria del proceso. Con POLL_OUTBOX_INLINE no hace falta Celery
    # para llenar la bandeja; el push sigue siendo best-effort.
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "asiscole-local",
        }
    }
else:
    CACHES = {
        "default": {
            "BACKEND": "django_redis.cache.RedisCache",
            "LOCATION": REDIS_URL,
            "OPTIONS": {
                "CLIENT_CLASS": "django_redis.client.DefaultClient",
                "IGNORE_EXCEPTIONS": True,
            },
            "KEY_PREFIX": "asiscole",
        }
    }

# Un Redis caido degrada, no tumba: el directorio vuelve a consultar la BD.
DJANGO_REDIS_IGNORE_EXCEPTIONS = True


# ---------------------------------------------------------------------------
# Celery
# ---------------------------------------------------------------------------

CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TIMEZONE = "America/Lima"
CELERY_ENABLE_UTC = True
CELERY_TASK_ACKS_LATE = True
CELERY_WORKER_PREFETCH_MULTIPLIER = 1
CELERY_BROKER_CONNECTION_RETRY_ON_STARTUP = True

# Planificacion de beat: poller de outbox, purga de retencion y directorio.
CELERY_BEAT_SCHEDULE = {
    "poller-outbox": {
        # Lee asis_outbox de cada colegio y encola la generacion de mensajes.
        "task": "apps.ingesta.tasks.poll_outbox_colegios",
        "schedule": 10.0,
        "options": {"expires": 9},
    },
    "purga-retencion-mensajes": {
        # Purga/anonimiza mensajes que superan MESSAGE_RETENTION_MONTHS (RNF-11).
        "task": "apps.mensajeria.tasks.purgar_mensajes_vencidos",
        "schedule": 24 * 60 * 60.0,
        "options": {"expires": 3600},
    },
    "reconciliar-directorio": {
        # Pasada nocturna que corrige las derivas de asis_directorio (ADR-05).
        # A las 02:30 de America/Lima, con el colegio cerrado.
        "task": "apps.directorio.tasks.reconciliar_directorio",
        "schedule": crontab(hour=2, minute=30),
        "options": {"expires": 3600},
    },
    "precalentar-directorio": {
        # Carga la cache antes de la jornada escolar, cuando llega el pico de
        # logins y de registros de entrada.
        "task": "apps.directorio.tasks.precalentar_directorio",
        "schedule": crontab(hour=6, minute=0),
        "options": {"expires": 1800},
    },
}


# ---------------------------------------------------------------------------
# Django REST Framework
# ---------------------------------------------------------------------------

REST_FRAMEWORK = {
    # El canal no usa la autenticacion de Django: cada endpoint de negocio exige
    # un data_token propio, validado por permisos de la app `cuentas`.
    "DEFAULT_AUTHENTICATION_CLASSES": [],
    # Denegar por defecto: una vista sin permiso explicito no queda abierta.
    "DEFAULT_PERMISSION_CLASSES": ["apps.common.permissions.DenegarPorDefecto"],
    "EXCEPTION_HANDLER": "apps.common.exception_handler.asiscole_exception_handler",
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "UNAUTHENTICATED_USER": None,
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
}

SPECTACULAR_SETTINGS = {
    "TITLE": "Asiscole — canal del apoderado",
    "DESCRIPTION": (
        "API del canal movil que notifica a los apoderados entradas, salidas, "
        "incidencias y avisos del colegio."
    ),
    "VERSION": "0.1.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "SCHEMA_PATH_PREFIX": "/v0.1",
    "COMPONENT_SPLIT_REQUEST": True,
}


# ---------------------------------------------------------------------------
# Internacionalizacion
# ---------------------------------------------------------------------------

LANGUAGE_CODE = "es-pe"
TIME_ZONE = "America/Lima"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"


# ---------------------------------------------------------------------------
# Constantes de negocio del SRS
# ---------------------------------------------------------------------------

# Tokens (RNF-01 / SRS 14.1)
SESSION_TOKEN_DAYS = env_int("SESSION_TOKEN_DAYS", 10)
SESSION_RENEW_WINDOW_DAYS = env_int("SESSION_RENEW_WINDOW_DAYS", 3)
DATA_TOKEN_MINUTES = env_int("DATA_TOKEN_MINUTES", 60)
TRANSFER_REQUEST_TTL_MINUTES = env_int("TRANSFER_REQUEST_TTL_MINUTES", 5)

# Rate limiting del login (SRS 14.3) — curva escalonada:
#   3 fallos → bloqueo 5 min; si sigue fallando → 10 min;
#   ~8 fallos acumulados en la ventana → bloqueo largo (24 h).
LOGIN_MAX_ATTEMPTS = env_int("LOGIN_MAX_ATTEMPTS", 3)
LOGIN_ATTEMPT_WINDOW_MINUTES = env_int("LOGIN_ATTEMPT_WINDOW_MINUTES", 60)
LOGIN_LOCKOUT_MINUTES = env_int("LOGIN_LOCKOUT_MINUTES", 5)
LOGIN_LOCKOUT_ESCALATED_MINUTES = env_int("LOGIN_LOCKOUT_ESCALATED_MINUTES", 10)
LOGIN_HARD_MAX_ATTEMPTS = env_int("LOGIN_HARD_MAX_ATTEMPTS", 8)
LOGIN_HARD_LOCKOUT_MINUTES = env_int("LOGIN_HARD_LOCKOUT_MINUTES", 1440)
TRANSFER_MAX_PER_HOUR = env_int("TRANSFER_MAX_PER_HOUR", 3)

# Retencion de mensajes en la BD central (RNF-11)
MESSAGE_RETENTION_MONTHS = env_int("MESSAGE_RETENTION_MONTHS", 24)

# Resiliencia multi-BD (SRS 7.8)
DIRECTORY_CACHE_TTL_SECONDS = env_int("DIRECTORY_CACHE_TTL_SECONDS", 86400)
CIRCUIT_BREAKER_FAILURES = env_int("CIRCUIT_BREAKER_FAILURES", 5)
CIRCUIT_BREAKER_COOLDOWN_SECONDS = env_int("CIRCUIT_BREAKER_COOLDOWN_SECONDS", 300)

# Push (rutas a credenciales; el envio lo implementa una fase posterior)
FCM_CREDENTIALS_PATH = env_str("FCM_CREDENTIALS_PATH")

# Clave compartida Asiscole → POST /ingesta/eventos (cabecera X-Asiscole-Ingest-Key).
# Si está vacía, el endpoint responde 401 a todas las peticiones.
INGEST_API_KEY = env_str("INGEST_API_KEY")
APNS_KEY_PATH = env_str("APNS_KEY_PATH")
APNS_KEY_ID = env_str("APNS_KEY_ID")
APNS_TEAM_ID = env_str("APNS_TEAM_ID")
APNS_TOPIC = env_str("APNS_TOPIC")


# ---------------------------------------------------------------------------
# Logging estructurado en JSON
# ---------------------------------------------------------------------------
# Ley N.o 29733: en los logs nunca van codigo_barras, telefonos, nombres de
# estudiantes, direcciones ni contenido de mensajes. Para correlacionar se usa
# el request_id y los identificadores internos.

LOG_LEVEL = env_str("DJANGO_LOG_LEVEL", "DEBUG" if DEBUG else "INFO").upper()

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {
        "request_id": {"()": "apps.common.logging.RequestIdFilter"},
    },
    "formatters": {
        "json": {"()": "apps.common.logging.JsonFormatter"},
    },
    "handlers": {
        "consola": {
            "class": "logging.StreamHandler",
            "formatter": "json",
            "filters": ["request_id"],
        },
    },
    "root": {"handlers": ["consola"], "level": LOG_LEVEL},
    "loggers": {
        "django": {"handlers": ["consola"], "level": LOG_LEVEL, "propagate": False},
        # Las consultas SQL pueden contener datos personales: nunca se emiten.
        "django.db.backends": {"handlers": ["consola"], "level": "WARNING", "propagate": False},
        "asiscole": {"handlers": ["consola"], "level": LOG_LEVEL, "propagate": False},
        "celery": {"handlers": ["consola"], "level": LOG_LEVEL, "propagate": False},
    },
}


# ---------------------------------------------------------------------------
# Seguridad
# ---------------------------------------------------------------------------

SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
USE_X_FORWARDED_HOST = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

if not DEBUG:
    SECURE_SSL_REDIRECT = env_bool("DJANGO_SECURE_SSL_REDIRECT", True)
    # La sonda de vida la consulta el orquestador por HTTP plano: no se redirige.
    SECURE_REDIRECT_EXEMPT = [r"^health$"]
    SECURE_HSTS_SECONDS = env_int("DJANGO_SECURE_HSTS_SECONDS", 31536000)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
