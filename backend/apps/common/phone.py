"""Normalizacion de telefonos y hashing de credenciales.

`estudiantes.telefono_contacto` es texto libre del sistema escolar y llega sucio.
Formatos reales observados:

    '987654321'         -> +51987654321   (nacional, sin prefijo)
    '+51 987 654 322'   -> +51987654322   (E.164 con espacios)
    '51987654323'       -> +51987654323   (prefijo pais sin '+')

Todo el canal trabaja unicamente con E.164. La comparacion del login y el indice
del directorio se hacen sobre el valor normalizado, nunca sobre el crudo.
"""

from __future__ import annotations

import hashlib
import re
import unicodedata

import phonenumbers
from phonenumbers import NumberParseException, PhoneNumberFormat

REGION_POR_DEFECTO = "PE"

#: Un campo puede traer varios telefonos ('987654321 / 999888777').
_SEPARADORES_DE_LISTA = re.compile(r"[/,;|\n]+| y ", flags=re.IGNORECASE)

#: Todo lo que no sea digito o '+' sobra (espacios, guiones, parentesis, puntos).
_RUIDO = re.compile(r"[^\d+]")


def _limpiar(valor: str) -> str:
    """Quita ruido tipografico dejando solo digitos y un eventual '+' inicial."""
    sin_acentos = unicodedata.normalize("NFKD", valor)
    limpio = _RUIDO.sub("", sin_acentos)
    if limpio.startswith("+"):
        return "+" + limpio.replace("+", "")
    return limpio.replace("+", "")


def _intentar(candidato: str, region: str) -> str | None:
    """Parsea un candidato y lo devuelve en E.164 si es un numero valido."""
    if not candidato:
        return None
    try:
        numero = phonenumbers.parse(candidato, region)
    except NumberParseException:
        return None
    if not phonenumbers.is_valid_number(numero):
        return None
    return phonenumbers.format_number(numero, PhoneNumberFormat.E164)


def _candidatos(limpio: str) -> list[str]:
    """Devuelve las lecturas posibles de una cadena ya limpia, en orden.

    Con '+' el prefijo de pais es explicito y no hay ambiguedad. Sin el, la misma
    cadena puede ser un numero nacional ('987654321'), uno internacional al que
    le falta el '+' ('51987654323') o uno escrito con prefijo de salida o cero
    nacional ('051987654321').
    """
    if limpio.startswith("+"):
        return [limpio]

    lista = [limpio, f"+{limpio}"]
    sin_ceros = limpio.lstrip("0")
    if sin_ceros and sin_ceros != limpio:
        lista.extend([sin_ceros, f"+{sin_ceros}"])
    return lista


def extraer_telefonos_e164(
    valor: str, region: str = REGION_POR_DEFECTO
) -> list[str]:
    """Extrae todos los telefonos E.164 de un campo (uno o varios).

    Soporta el caso N:M pragmatico de hoy: `telefono_contacto` con
    '987654321 / 999888777' (mama y papa) sin tabla intermedia nueva.
    """
    if valor is None:
        return []
    texto = str(valor).strip()
    if not texto:
        return []

    hallados: list[str] = []
    # Primero el campo entero (un solo numero); luego cada fragmento.
    fragmentos = [texto, *_SEPARADORES_DE_LISTA.split(texto)]
    for fragmento in fragmentos:
        limpio = _limpiar(fragmento)
        if not limpio:
            continue
        for candidato in _candidatos(limpio):
            resultado = _intentar(candidato, region)
            if resultado and resultado not in hallados:
                hallados.append(resultado)
                break
    return hallados


def normalizar_e164(valor: str, region: str = REGION_POR_DEFECTO) -> str | None:
    """Normaliza un telefono a E.164 (el primero si el campo trae varios).

    Args:
        valor: Telefono tal como viene de la BD del colegio o del formulario.
        region: Region por defecto cuando el numero no trae prefijo de pais.

    Returns:
        El numero en E.164 (por ejemplo `+51987654321`), o `None` si el valor no
        contiene un telefono valido.

    Note:
        El resultado es un dato personal: sirve para buscar y comparar, nunca
        para escribirlo en un log. Para varios numeros usa `extraer_telefonos_e164`.
    """
    hallados = extraer_telefonos_e164(valor, region=region)
    return hallados[0] if hallados else None


def hash_credencial(telefono: str, codigo: str) -> str:
    """Devuelve el SHA-256 del par (telefono, documento) para `asis_intento_login`.

    El control de intentos fallidos (SRS 14.3) necesita agrupar por credencial,
    pero guardar el telefono o el `codigo_barras` en claro en una tabla de
    intentos seria almacenar datos de un menor sin necesidad. Se guarda solo este
    hash, que permite contar y bloquear sin poder leer el dato original.

    Args:
        telefono: Telefono del apoderado; se normaliza antes de hashear para que
            '987654321' y '+51 987 654 321' produzcan el mismo hash.
        codigo: `estudiantes.codigo_barras` (el "DNI" del login).

    Returns:
        Hash hexadecimal de 64 caracteres.
    """
    telefono_normalizado = normalizar_e164(telefono or "") or _limpiar(str(telefono or ""))
    codigo_normalizado = str(codigo or "").strip().upper()
    # El separador evita colisiones entre pares distintos que concatenados
    # darian la misma cadena.
    material = f"{telefono_normalizado}\x1f{codigo_normalizado}".encode("utf-8")
    return hashlib.sha256(material).hexdigest()
