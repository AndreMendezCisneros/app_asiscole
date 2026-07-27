"""Pruebas de humo del scaffold: configuracion, router y catalogo de errores.

No tocan la BD: solo comprueban que el andamiaje esta bien cableado.
"""

from __future__ import annotations

import pytest
from django.conf import settings

from apps.common import errors
from config.db_router import TenantRouter, es_alias_de_colegio, tenant_alias


def test_localizacion_peruana():
    assert settings.LANGUAGE_CODE == "es-pe"
    assert settings.TIME_ZONE == "America/Lima"
    assert settings.USE_TZ is True


def test_health_incluye_fcm_disponible(api):
    import json

    resp = api.get("/health")
    assert resp.status_code == 200
    cuerpo = json.loads(resp.content.decode("utf-8"))
    assert cuerpo["status"] == "ok"
    assert "fcm_disponible" in cuerpo
    assert isinstance(cuerpo["fcm_disponible"], bool)


def test_bd_central_y_router_configurados():
    # En produccion la BD central es PostgreSQL. Bajo pytest la conexion
    # `default` se sustituye por SQLite en memoria (ver config/settings.py), asi
    # que se comprueba el motor declarado, no el que usa la propia suite.
    assert settings.CENTRAL_DB_ENGINE == "django.db.backends.postgresql"
    assert settings.DATABASE_ROUTERS == ["config.db_router.TenantRouter"]


def test_rest_framework_deniega_por_defecto():
    assert settings.REST_FRAMEWORK["DEFAULT_AUTHENTICATION_CLASSES"] == []
    assert settings.REST_FRAMEWORK["DEFAULT_PERMISSION_CLASSES"] == [
        "apps.common.permissions.DenegarPorDefecto"
    ]
    assert settings.REST_FRAMEWORK["EXCEPTION_HANDLER"] == (
        "apps.common.exception_handler.asiscole_exception_handler"
    )


def test_alias_de_tenant():
    assert tenant_alias("jean_piaget") == "colegio_jean_piaget"
    assert es_alias_de_colegio("colegio_jean_piaget") is True
    assert es_alias_de_colegio("default") is False
    with pytest.raises(ValueError):
        tenant_alias("  ")


def test_el_router_nunca_migra_colegios_ni_academico():
    router = TenantRouter()
    assert router.allow_migrate("colegio_jean_piaget", "cuentas") is False
    assert router.allow_migrate("colegio_jean_piaget", "academico") is False
    assert router.allow_migrate("default", "academico") is False
    assert router.allow_migrate("default", "cuentas") is True


def test_el_router_no_escribe_en_las_bd_de_colegio():
    from apps.academico.models import Estudiante

    router = TenantRouter()
    assert router.db_for_write(Estudiante) is None
    assert router.db_for_read(Estudiante) is None


@pytest.mark.parametrize(
    ("clase", "estado", "codigo"),
    [
        (errors.ValidationError, 400, "VALIDATION_ERROR"),
        (errors.Unauthenticated, 401, "UNAUTHENTICATED"),
        (errors.AccountSuspended, 403, "ACCOUNT_SUSPENDED"),
        (errors.RoleNotAllowed, 403, "ROLE_NOT_ALLOWED"),
        (errors.StudentLinkNotFound, 404, "STUDENT_LINK_NOT_FOUND"),
        (errors.SessionAlreadyActive, 409, "SESSION_ALREADY_ACTIVE"),
        (errors.TransferAlreadyPending, 409, "TRANSFER_ALREADY_PENDING"),
        (errors.SessionExpired, 410, "SESSION_EXPIRED"),
        (errors.TransferExpired, 410, "TRANSFER_EXPIRED"),
        (errors.AccountLocked, 423, "ACCOUNT_LOCKED"),
        (errors.TooManyRequests, 429, "TOO_MANY_REQUESTS"),
        (errors.UpstreamSchoolDbUnavailable, 503, "UPSTREAM_SCHOOL_DB_UNAVAILABLE"),
    ],
)
def test_catalogo_de_errores(clase, estado, codigo):
    error = clase()
    assert error.status_code == estado
    assert error.code == codigo
    assert error.message


def test_student_link_not_found_no_revela_que_dato_fallo():
    mensaje = errors.StudentLinkNotFound().message.lower()
    for pista in ("teléfono", "telefono", "documento", "dni", "código", "codigo"):
        assert pista not in mensaje


def test_manejador_devuelve_el_cuerpo_uniforme(rf):
    from apps.common.exception_handler import asiscole_exception_handler

    peticion = rf.get("/v0.1/mensajes")
    peticion.request_id = "abc123"
    respuesta = asiscole_exception_handler(errors.SessionExpired(), {"request": peticion})

    assert respuesta.status_code == 410
    assert set(respuesta.data) == {"code", "message", "request_id"}
    assert respuesta.data["code"] == "SESSION_EXPIRED"
    assert respuesta.data["request_id"] == "abc123"


def test_los_modelos_academicos_no_son_gestionados():
    from apps.academico import models as academico

    esperado = {
        academico.Estudiante: "estudiantes",
        academico.RegistroLlegada: "registros_llegada",
        academico.Incidencia: "incidencias",
        academico.CatalogoFalta: "catalogo_faltas",
        academico.EvidenciaFotografica: "evidencias_fotograficas",
        academico.UsuarioColegio: "usuarios",
        academico.PadreEstudiante: "padres_estudiantes",
    }
    for modelo, tabla in esperado.items():
        assert modelo._meta.managed is False, modelo.__name__
        assert modelo._meta.db_table == tabla


def test_constantes_del_srs_presentes():
    for nombre in (
        "SESSION_TOKEN_DAYS",
        "SESSION_RENEW_WINDOW_DAYS",
        "DATA_TOKEN_MINUTES",
        "TRANSFER_REQUEST_TTL_MINUTES",
        "LOGIN_MAX_ATTEMPTS",
        "LOGIN_ATTEMPT_WINDOW_MINUTES",
        "LOGIN_LOCKOUT_MINUTES",
        "LOGIN_LOCKOUT_ESCALATED_MINUTES",
        "LOGIN_HARD_MAX_ATTEMPTS",
        "LOGIN_HARD_LOCKOUT_MINUTES",
        "TRANSFER_MAX_PER_HOUR",
        "MESSAGE_RETENTION_MONTHS",
        "DIRECTORY_CACHE_TTL_SECONDS",
        "CIRCUIT_BREAKER_FAILURES",
        "CIRCUIT_BREAKER_COOLDOWN_SECONDS",
        "SCHOOL_DB_TIMEOUT_SECONDS",
    ):
        assert isinstance(getattr(settings, nombre), int)
