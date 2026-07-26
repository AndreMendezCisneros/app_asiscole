"""Pruebas del logging JSON: formato estable y sin datos personales."""

from __future__ import annotations

import json
import logging

from apps.common.logging import JsonFormatter, RequestIdFilter, reset_request_id, set_request_id


def _formatear(**extra) -> dict:
    """Emite un registro con el formatter real y devuelve el JSON parseado."""
    registro = logging.LogRecord(
        name="asiscole.pruebas",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="login",
        args=(),
        exc_info=None,
    )
    for clave, valor in extra.items():
        setattr(registro, clave, valor)
    RequestIdFilter().filter(registro)
    return json.loads(JsonFormatter().format(registro))


def test_emite_los_campos_fijos():
    token = set_request_id("req-1")
    try:
        salida = _formatear(tenant="jean_piaget", resultado="denegado")
    finally:
        reset_request_id(token)

    assert salida["level"] == "INFO"
    assert salida["logger"] == "asiscole.pruebas"
    assert salida["message"] == "login"
    assert salida["request_id"] == "req-1"
    assert salida["tenant"] == "jean_piaget"
    assert salida["resultado"] == "denegado"
    assert salida["timestamp"]


def test_redacta_los_campos_que_parecen_datos_personales():
    salida = _formatear(telefono="+51987654321", codigo_barras="20481234", tenant="jean_piaget")

    assert salida["telefono"] == "[redactado]"
    assert salida["codigo_barras"] == "[redactado]"
    assert "+51987654321" not in json.dumps(salida)
    assert "20481234" not in json.dumps(salida)
    assert salida["tenant"] == "jean_piaget"


def test_redacta_tambien_dentro_de_diccionarios():
    salida = _formatear(datos={"tenant": "jean_piaget", "nombre_completo": "Juan Pérez"})

    assert salida["datos"]["tenant"] == "jean_piaget"
    assert salida["datos"]["nombre_completo"] == "[redactado]"
