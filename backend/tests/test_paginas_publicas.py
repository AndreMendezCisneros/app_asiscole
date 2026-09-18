"""Las páginas públicas de Play (baja y privacidad) no piden datos personales."""

from __future__ import annotations

from django.test import Client

from apps.common.paginas import CORREO_SOPORTE, NOMBRE_APP


def test_eliminar_cuenta_es_publica_y_explica_el_procedimiento():
    respuesta = Client().get("/eliminar-cuenta")
    assert respuesta.status_code == 200
    cuerpo = respuesta.content.decode("utf-8")
    assert "Eliminar mi cuenta" in cuerpo
    assert "Perfil" in cuerpo
    assert "no se puede deshacer" in cuerpo
    assert NOMBRE_APP in cuerpo
    assert CORREO_SOPORTE in cuerpo


def test_eliminar_cuenta_no_pide_datos_del_estudiante():
    """Sin formulario: por correo no se tramitan datos de menores."""
    cuerpo = Client().get("/eliminar-cuenta").content.decode("utf-8")
    assert "<form" not in cuerpo
    assert "<input" not in cuerpo


def test_privacidad_es_publica_y_nombra_la_ley():
    respuesta = Client().get("/privacidad")
    assert respuesta.status_code == 200
    cuerpo = respuesta.content.decode("utf-8")
    assert "Politica de privacidad" in cuerpo
    assert "29733" in cuerpo
    assert CORREO_SOPORTE in cuerpo
    assert "pe.asiscole.asiscole_app" in cuerpo
    assert "<form" not in cuerpo
