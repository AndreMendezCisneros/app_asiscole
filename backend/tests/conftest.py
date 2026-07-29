"""Fixtures compartidas de la suite del nucleo (directorio + cuentas).

Dos decisiones que valen para toda la suite:

* La cache se sustituye por una `LocMemCache` con una ubicacion distinta en cada
  prueba. Hace de Redis de mentira y garantiza que un contador de rate limiting
  no se filtre de una prueba a la siguiente.
* Las BDs de colegio NUNCA se tocan. `SCHOOL_DATABASES` esta vacio y lo que se
  simula es `apps.directorio.repositorio.consultar_colegio`, que es la frontera
  exacta entre el canal y el sistema escolar.
"""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest
from django.utils import timezone
from rest_framework.test import APIClient

from apps.cuentas.models import SESION_ACTIVA, Apoderado, SesionActiva
from apps.directorio.dto import VinculoDTO
from apps.directorio.models import Directorio

#: Datos de mentira usados por casi todas las pruebas.
TELEFONO = "+51987654321"
DOCUMENTO = "70123456"
TENANT = "jean_piaget"
DEVICE_A = "device-a"
DEVICE_B = "device-b"


@pytest.fixture(autouse=True)
def clave_de_firma(settings):
    """Usa una clave HS256 de longitud realista (>= 32 bytes, RFC 7518)."""
    settings.SECRET_KEY = "clave-de-pruebas-de-64-caracteres-para-firmar-los-jwt-del-canal!"


@pytest.fixture(autouse=True)
def sin_redireccion_https(settings):
    """Desactiva `SECURE_SSL_REDIRECT` durante las pruebas.

    Con `DEBUG=False` Django responde 301 a todo lo que llega por HTTP plano,
    que es justo lo que hace el cliente de pruebas. En produccion la redireccion
    sigue activa.
    """
    settings.SECURE_SSL_REDIRECT = False


@pytest.fixture(autouse=True)
def cache_en_memoria(settings):
    """Reemplaza Redis por una cache en memoria aislada por prueba."""
    settings.CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": f"pruebas-{uuid.uuid4()}",
        }
    }
    from django.core.cache import cache

    cache.clear()
    yield cache
    cache.clear()


@pytest.fixture
def colegios(settings):
    """Declara dos colegios de mentira, sin conexion real a ninguna BD."""
    settings.SCHOOL_TENANTS = {TENANT: "Jean Piaget", "san_agustin": "San Agustin"}
    return settings.SCHOOL_TENANTS


@pytest.fixture
def api() -> APIClient:
    """Cliente HTTP de DRF."""
    return APIClient()


def crear_vinculo(
    *,
    telefono: str = TELEFONO,
    documento: str = DOCUMENTO,
    tenant_id: str = TENANT,
    id_estudiante: int = 101,
) -> VinculoDTO:
    """Construye un `VinculoDTO` de prueba."""
    return VinculoDTO(
        tenant_id=tenant_id,
        id_estudiante=id_estudiante,
        codigo_barras=documento,
        nombre_estudiante="Estudiante De Prueba",
        telefono=telefono,
        grado="3",
        seccion="A",
        nivel="Primaria",
    )


@pytest.fixture
def vinculo_en_directorio(db) -> Directorio:
    """Deja el vinculo ya proyectado en `asis_directorio`.

    Con esto el resolvedor se detiene en el paso 2 (BD central) y el login no
    necesita ninguna BD de colegio.
    """
    return Directorio.objects.create(
        telefono=TELEFONO,
        tenant_id=TENANT,
        id_estudiante=101,
        codigo_barras=DOCUMENTO,
        nombre_estudiante="Estudiante De Prueba",
        grado="3",
        seccion="A",
        nivel="Primaria",
        origen="resuelto_automatico",
        estado_vinculo="activo",
        sincronizado_en=timezone.now(),
    )


@pytest.fixture
def apoderado(db) -> Apoderado:
    """Cuenta ya existente para el telefono de prueba."""
    return Apoderado.objects.create(telefono=TELEFONO)


def crear_sesion(apoderado_obj: Apoderado, device_id: str = DEVICE_A, **extra) -> SesionActiva:
    """Crea una sesion activa para una cuenta."""
    valores = {
        "device_id": device_id,
        "jti": uuid.uuid4(),
        "estado": SESION_ACTIVA,
        "expira_en": timezone.now() + timedelta(days=10),
    }
    valores.update(extra)
    return SesionActiva.objects.create(apoderado=apoderado_obj, **valores)


def cuerpo_login(**extra) -> dict:
    """Cuerpo minimo valido de `POST /v0.1/auth/login`."""
    from django.conf import settings

    cuerpo = {
        "telefono": TELEFONO,
        "documento_estudiante": DOCUMENTO,
        "device_id": DEVICE_A,
        "acepta_terminos": True,
        "terminos_version": settings.TERMINOS_VERSION,
    }
    cuerpo.update(extra)
    return cuerpo


def con_bearer(token: str) -> dict:
    """Devuelve los kwargs de cabecera para autenticar una peticion."""
    return {"HTTP_AUTHORIZATION": f"Bearer {token}"}
