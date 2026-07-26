"""Pruebas de carrera en la renovación de sesión (ventana día 7–10).

Documenta el comportamiento esperado: dos renovaciones concurrentes no deben
dejar dos sesiones activas ni romper el índice único parcial.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from django.utils import timezone

from apps.cuentas.models import SESION_ACTIVA, Apoderado, SesionActiva
from apps.cuentas import tokens


@pytest.mark.django_db(transaction=True)
def test_una_sola_sesion_activa_bajo_carrera():
    apo = Apoderado.objects.create(telefono="+51966666666")
    ahora = timezone.now()
    SesionActiva.objects.create(
        apoderado=apo,
        device_id="dev-a",
        jti=tokens.nuevo_jti() if hasattr(tokens, "nuevo_jti") else __import__("uuid").uuid4(),
        estado=SESION_ACTIVA,
        creada_en=ahora - timedelta(days=8),
        ultima_actividad_en=ahora,
        expira_en=ahora + timedelta(days=2),
    )

    def intentar_segunda():
        try:
            SesionActiva.objects.create(
                apoderado=apo,
                device_id="dev-b",
                jti=__import__("uuid").uuid4(),
                estado=SESION_ACTIVA,
                creada_en=ahora,
                ultima_actividad_en=ahora,
                expira_en=ahora + timedelta(days=10),
            )
            return "ok"
        except Exception:
            return "conflicto"

    with ThreadPoolExecutor(max_workers=4) as pool:
        resultados = list(pool.map(lambda _: intentar_segunda(), range(4)))

    activas = SesionActiva.objects.filter(apoderado=apo, estado=SESION_ACTIVA).count()
    assert activas == 1
    assert "conflicto" in resultados
