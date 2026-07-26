"""Pruebas de normalizacion de telefonos y de hashing de credenciales.

Los numeros usados son ficticios: no corresponden a ningun apoderado real.
"""

from __future__ import annotations

import pytest

from apps.common.phone import extraer_telefonos_e164, hash_credencial, normalizar_e164


@pytest.mark.parametrize(
    ("crudo", "esperado"),
    [
        # Los tres formatos que aparecen de verdad en telefono_contacto.
        ("987654321", "+51987654321"),
        ("+51 987 654 322", "+51987654322"),
        ("51987654323", "+51987654323"),
        # Variantes tipograficas del mismo numero.
        ("  987 654 321  ", "+51987654321"),
        ("987-654-321", "+51987654321"),
        ("(51) 987654321", "+51987654321"),
        ("+51-987-654-321", "+51987654321"),
        ("051987654321", "+51987654321"),
    ],
)
def test_normaliza_formatos_reales(crudo, esperado):
    assert normalizar_e164(crudo) == esperado


@pytest.mark.parametrize(
    "basura",
    [
        None,
        "",
        "   ",
        "-",
        "no tiene",
        "sin numero",
        "123",
        "000000000",
        "12345",
        "abcdefghi",
        "+++",
        "9876543210987654321",
    ],
)
def test_devuelve_none_ante_basura(basura):
    assert normalizar_e164(basura) is None


def test_toma_el_primer_numero_cuando_el_campo_trae_varios():
    assert normalizar_e164("987654321 / 999888777") == "+51987654321"
    assert normalizar_e164("Mamá: 987654321, Papá: 999888777") == "+51987654321"


def test_extrae_todos_los_numeros_del_campo():
    assert extraer_telefonos_e164("987654321 / 999888777") == [
        "+51987654321",
        "+51999888777",
    ]
    assert extraer_telefonos_e164("Mamá: 987654321, Papá: 999888777") == [
        "+51987654321",
        "+51999888777",
    ]
    assert extraer_telefonos_e164("987654321") == ["+51987654321"]
    assert extraer_telefonos_e164("") == []


def test_normalizacion_es_idempotente():
    una_vez = normalizar_e164("987654321")
    assert normalizar_e164(una_vez) == una_vez


def test_respeta_otra_region_cuando_se_indica():
    assert normalizar_e164("+56 9 6789 0123", region="CL") == "+56967890123"


def test_hash_credencial_es_estable_y_no_revela_el_dato():
    esperado = hash_credencial("987654321", "20481234")
    assert len(esperado) == 64
    assert "987654321" not in esperado
    assert "20481234" not in esperado
    # El mismo telefono en otro formato produce el mismo hash.
    assert hash_credencial("+51 987 654 321", "20481234") == esperado
    assert hash_credencial("51987654321", " 20481234 ") == esperado


def test_hash_credencial_distingue_credenciales_distintas():
    assert hash_credencial("987654321", "20481234") != hash_credencial("987654321", "20481235")
    assert hash_credencial("987654321", "20481234") != hash_credencial("987654322", "20481234")
    # El separador impide que pares distintos concatenen a la misma cadena.
    assert hash_credencial("98765", "432120481234") != hash_credencial("987654321", "20481234")
    assert hash_credencial("987", "654321") != hash_credencial("987654", "321")
