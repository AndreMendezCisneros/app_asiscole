"""Acceso de solo lectura a las BDs de colegio para poblar el directorio.

Es el unico punto del canal que sabe que el vinculo telefono -> estudiante nace
de `estudiantes.telefono_contacto`. Se consulta la vista
`asis_v_directorio_origen` (creada por `db/migrations/001_colegio_outbox.sql`),
que ya expone `telefono_digitos` con la misma expresion que el indice funcional
`asis_idx_estudiantes_tel_norm`. Comparar contra esa columna deja que el planner
use el indice en lugar de recorrer la tabla entera.

El alias de conexion se resuelve siempre con `config.db_router.tenant_alias`; el
`tenant_id` viene de la configuracion o del directorio, jamas del cliente.
"""

from __future__ import annotations

import logging
from collections.abc import Iterator

import phonenumbers
from django.db import connections

from apps.common.phone import extraer_telefonos_e164
from apps.directorio.dto import VinculoDTO
from apps.directorio.models import VINCULO_ACTIVO
from config.db_router import tenant_alias

logger = logging.getLogger("asiscole.directorio")

#: Columnas que el canal necesita de la vista. Se pide lo minimo (Ley N.o 29733).
_COLUMNAS = (
    "id_estudiante, codigo_barras, nombre_completo, grado, seccion, "
    "nivel_educativo, telefono_contacto"
)

_SQL_POR_TELEFONO = f"""
    SELECT {_COLUMNAS}
      FROM public.asis_v_directorio_origen
     WHERE activo = TRUE
       AND telefono_digitos = ANY(%s)
"""

_SQL_TODOS = f"""
    SELECT {_COLUMNAS}
      FROM public.asis_v_directorio_origen
     WHERE activo = TRUE
"""

#: Filas que se traen por viaje en la reconciliacion nocturna.
TAMANO_LOTE = 1000


def candidatos_digitos(telefono_e164: str) -> list[str]:
    """Devuelve las formas en digitos con las que un colegio pudo guardar el numero.

    `telefono_contacto` es texto libre y el mismo abonado aparece como
    '987654321', '+51 987 654 321' o '51987654321'. La vista los reduce todos a
    digitos, asi que basta comparar contra las variantes plausibles del numero
    buscado.

    Args:
        telefono_e164: Telefono normalizado, por ejemplo `+51987654321`.

    Returns:
        Lista de cadenas de digitos, sin repetidos y en orden estable.
    """
    limpio = (telefono_e164 or "").strip()
    if not limpio:
        return []

    solo_digitos = "".join(caracter for caracter in limpio if caracter.isdigit())
    variantes = [solo_digitos]

    try:
        numero = phonenumbers.parse(limpio, None)
    except phonenumbers.NumberParseException:
        numero = None

    if numero is not None:
        nacional = str(numero.national_number)
        variantes.extend([nacional, f"0{nacional}", f"{numero.country_code}{nacional}"])

    vistos: list[str] = []
    for variante in variantes:
        if variante and variante not in vistos:
            vistos.append(variante)
    return vistos


def _fila_a_vinculo(fila: tuple, tenant_id: str, telefono: str) -> VinculoDTO:
    """Convierte una fila cruda de la vista en un `VinculoDTO`."""
    id_estudiante, codigo_barras, nombre, grado, seccion, nivel, _telefono_crudo = fila
    return VinculoDTO(
        tenant_id=tenant_id,
        id_estudiante=int(id_estudiante),
        codigo_barras=str(codigo_barras),
        nombre_estudiante=str(nombre),
        telefono=telefono,
        grado=grado,
        seccion=seccion,
        nivel=nivel,
        estado_vinculo=VINCULO_ACTIVO,
    )


def consultar_colegio(tenant_id: str, telefono_e164: str) -> list[VinculoDTO]:
    """Busca en un colegio los estudiantes cuyo contacto es ese telefono.

    Args:
        tenant_id: Colegio a consultar.
        telefono_e164: Telefono normalizado del apoderado.

    Returns:
        Los vinculos hallados; lista vacia si el colegio no conoce el numero.

    Raises:
        django.db.Error: Si la BD del colegio no responde. El resolvedor lo
            traduce en un fallo del circuito, nunca en un 404.
    """
    candidatos = candidatos_digitos(telefono_e164)
    if not candidatos:
        return []

    alias = tenant_alias(tenant_id)
    with connections[alias].cursor() as cursor:
        cursor.execute(_SQL_POR_TELEFONO, [candidatos])
        filas = cursor.fetchall()

    vinculos: list[VinculoDTO] = []
    for fila in filas:
        # El campo puede traer varios numeros; basta que uno coincida.
        telefonos = extraer_telefonos_e164(fila[-1] or "")
        if telefono_e164 not in telefonos:
            continue
        vinculos.append(_fila_a_vinculo(fila, tenant_id, telefono_e164))
    return vinculos


def iterar_directorio(tenant_id: str) -> Iterator[VinculoDTO]:
    """Recorre el directorio completo de un colegio, por lotes.

    Lo usa la reconciliacion nocturna. Las filas cuyo telefono no se puede
    normalizar se descartan: sin E.164 no hay forma de enrutar nada.
    Si `telefono_contacto` trae varios numeros, emite un vinculo por cada uno
    (mismo estudiante, distinto telefono) para el N:M pragmatico.

    Yields:
        Un `VinculoDTO` por (estudiante, telefono) con contacto valido.
    """
    alias = tenant_alias(tenant_id)
    with connections[alias].cursor() as cursor:
        cursor.execute(_SQL_TODOS)
        while True:
            filas = cursor.fetchmany(TAMANO_LOTE)
            if not filas:
                return
            for fila in filas:
                for telefono in extraer_telefonos_e164(fila[-1] or ""):
                    yield _fila_a_vinculo(fila, tenant_id, telefono)
