"""Objeto de transporte del directorio.

`VinculoDTO` es lo que devuelve el resolvedor, venga de Redis, de la BD central o
de la BD de un colegio. Las capas superiores (login, perfil, mensajeria) trabajan
siempre contra esta forma y no contra un modelo de Django, para que da igual de
donde salio el dato.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

from apps.directorio.models import Directorio, VINCULO_ACTIVO


@dataclass(frozen=True)
class VinculoDTO:
    """Un estudiante vinculado a un telefono, con su colegio de origen.

    Attributes:
        tenant_id: Colegio al que pertenece el estudiante. Sale del directorio,
            nunca del cliente (ADR-03).
        id_estudiante: PK del estudiante dentro de la BD de ese colegio.
        codigo_barras: Documento del estudiante que se compara en el login.
        estado_vinculo: `activo` o `inactivo`; solo los activos habilitan acceso.
    """

    tenant_id: str
    id_estudiante: int
    codigo_barras: str
    nombre_estudiante: str
    telefono: str = ""
    grado: str | None = None
    seccion: str | None = None
    nivel: str | None = None
    relacion: str | None = "apoderado"
    estado_vinculo: str = VINCULO_ACTIVO

    @property
    def activo(self) -> bool:
        """Indica si el vinculo habilita acceso al estudiante."""
        return self.estado_vinculo == VINCULO_ACTIVO

    def como_dict(self) -> dict:
        """Serializa el vinculo para guardarlo en Redis."""
        return asdict(self)

    @classmethod
    def desde_dict(cls, datos: dict) -> VinculoDTO:
        """Reconstruye un vinculo leido de Redis.

        Ignora claves desconocidas para que un cambio de forma del DTO no
        reviente al leer una entrada de cache escrita por la version anterior.
        """
        campos = {clave: datos[clave] for clave in cls.__dataclass_fields__ if clave in datos}
        return cls(**campos)

    @classmethod
    def desde_modelo(cls, fila: Directorio) -> VinculoDTO:
        """Convierte una fila de `asis_directorio` en un DTO."""
        return cls(
            tenant_id=fila.tenant_id,
            id_estudiante=fila.id_estudiante,
            codigo_barras=fila.codigo_barras,
            nombre_estudiante=fila.nombre_estudiante,
            telefono=fila.telefono,
            grado=fila.grado,
            seccion=fila.seccion,
            nivel=fila.nivel,
            relacion=fila.relacion,
            estado_vinculo=fila.estado_vinculo or VINCULO_ACTIVO,
        )
