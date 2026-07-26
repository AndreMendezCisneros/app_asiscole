"""Configuracion global de pytest para el backend del canal Asiscole.

Fija valores de entorno deterministas ANTES de que pytest-django importe
`config.settings`, para que la suite no dependa del `.env` de la maquina y para
que ningun test toque por accidente la BD de un colegio real: `SCHOOL_DATABASES`
se deja vacio salvo que el propio test declare colegios de mentira.
"""

from __future__ import annotations

import os

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
os.environ.setdefault("DJANGO_SECRET_KEY", "clave-solo-para-pruebas")
os.environ.setdefault("DJANGO_DEBUG", "False")
os.environ.setdefault("DJANGO_ALLOWED_HOSTS", "testserver,localhost")
os.environ.setdefault("SCHOOL_DATABASES", "[]")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/1")

import pytest  # noqa: E402  (debe importarse despues de fijar el entorno)


@pytest.fixture
def cache_limpia(settings):
    """Sustituye Redis por una cache en memoria y la vacia al terminar."""
    settings.CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "pruebas",
        }
    }
    from django.core.cache import cache

    cache.clear()
    yield cache
    cache.clear()


@pytest.fixture
def celery_sincrono(settings):
    """Ejecuta las tareas de Celery en el acto, sin worker ni broker."""
    settings.CELERY_TASK_ALWAYS_EAGER = True
    settings.CELERY_TASK_EAGER_PROPAGATES = True
    return settings
