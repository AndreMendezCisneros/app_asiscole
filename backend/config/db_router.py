"""Enrutado de bases de datos del canal Asiscole.

Hay dos mundos:

* La **BD central** (alias ``default``): apps propias del canal (``cuentas``,
  ``directorio``, ``mensajeria``, ``administracion``, ``common``). Se lee, se
  escribe y se migra con normalidad.
* Las **BDs de colegio** (alias ``colegio_<tenant_id>``): son las bases del
  sistema escolar existente. La app ``academico`` las mapea con ``managed = False``
  y el canal las trata como SOLO LECTURA. Nunca se migran ni se escriben.

El alias de colegio se resuelve SIEMPRE desde el directorio telefonico de la BD
central (el vinculo apoderado -> colegio), JAMAS desde un valor que venga del
cliente. Aceptar un ``tenant_id`` del request permitiria saltar de colegio y leer
datos de menores de otro centro educativo.
"""

from __future__ import annotations

#: Prefijo de los alias de conexion de cada colegio.
TENANT_ALIAS_PREFIX = "colegio_"

#: Apps del canal que viven en la BD central.
APPS_CENTRALES = frozenset(
    {
        "common",
        "cuentas",
        "directorio",
        "mensajeria",
        "administracion",
        "ingesta",
        # Apps de infraestructura de Django que puedan necesitar tablas.
        "contenttypes",
        "sessions",
    }
)

#: App de solo lectura contra las BDs de colegio.
APP_ACADEMICO = "academico"


def tenant_alias(tenant_id: str) -> str:
    """Traduce un ``tenant_id`` del directorio al alias de conexion de Django.

    Args:
        tenant_id: Identificador del colegio tal como aparece en
            ``SCHOOL_DATABASES`` y en el directorio de la BD central.

    Returns:
        El alias ``colegio_<tenant_id>`` que se pasa a ``.using(...)``.

    Raises:
        ValueError: Si el ``tenant_id`` viene vacio.

    Note:
        Este valor procede del directorio, nunca del input del usuario. Quien
        llame a esta funcion ya debe haber verificado que el apoderado autenticado
        pertenece a ese colegio.
    """
    limpio = (tenant_id or "").strip()
    if not limpio:
        raise ValueError("tenant_id vacio: el alias de colegio no se puede resolver")
    return f"{TENANT_ALIAS_PREFIX}{limpio}"


def es_alias_de_colegio(alias: str) -> bool:
    """Indica si un alias de conexion corresponde a la BD de un colegio."""
    return bool(alias) and alias.startswith(TENANT_ALIAS_PREFIX)


class TenantRouter:
    """Router que separa la BD central de las BDs de colegio.

    Las lecturas de ``academico`` requieren un ``using`` explicito (lo pone el
    repositorio a partir del directorio); el router no adivina un colegio por
    defecto para evitar consultar el tenant equivocado.
    """

    def db_for_read(self, model, **hints):
        """Devuelve el alias de lectura, o ``None`` para dejar decidir a Django."""
        if model._meta.app_label == APP_ACADEMICO:
            # El alias correcto lo aporta quien consulta, con `.using(alias)`.
            # Devolver None en vez de "default" evita que una consulta sin tenant
            # termine buscando tablas del colegio dentro de la BD central.
            instancia = hints.get("instance")
            if instancia is not None:
                return instancia._state.db
            return None
        return "default"

    def db_for_write(self, model, **hints):
        """El canal nunca escribe en un colegio: solo la BD central admite escritura."""
        if model._meta.app_label == APP_ACADEMICO:
            return None
        return "default"

    def allow_relation(self, obj1, obj2, **hints):
        """Permite relaciones solo entre objetos de la misma conexion."""
        db1 = obj1._state.db
        db2 = obj2._state.db
        if db1 is None or db2 is None:
            return None
        return db1 == db2

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        """Bloquea toda migracion sobre colegios y sobre la app ``academico``.

        El esquema del colegio es intocable: ni tablas nuevas, ni ALTER, ni la
        tabla ``django_migrations``.
        """
        if es_alias_de_colegio(db):
            return False
        if app_label == APP_ACADEMICO:
            return False
        if db == "default":
            return True
        return False
