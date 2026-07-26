"""Proyecto Django del canal Asiscole.

Se importa la app de Celery al arrancar Django para que el decorador
``@shared_task`` de cada app quede asociado a esta instancia.
"""

from config.celery import app as celery_app

__all__ = ("celery_app",)
