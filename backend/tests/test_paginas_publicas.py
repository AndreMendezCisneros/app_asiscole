"""La página de eliminación de cuenta es un requisito de Google Play."""

from __future__ import annotations

from django.test import Client


def test_eliminar_cuenta_es_publica_y_explica_el_procedimiento():
    respuesta = Client().get("/eliminar-cuenta")
    assert respuesta.status_code == 200
    cuerpo = respuesta.content.decode("utf-8")
    # Play revisa que la página diga cómo pedir la eliminación y qué se borra.
    assert "Eliminar mi cuenta" in cuerpo
    assert "Perfil" in cuerpo
    assert "no se puede deshacer" in cuerpo


def test_eliminar_cuenta_no_pide_datos_del_estudiante():
    """Sin formulario: por correo no se tramitan datos de menores."""
    cuerpo = Client().get("/eliminar-cuenta").content.decode("utf-8")
    assert "<form" not in cuerpo
    assert "<input" not in cuerpo
