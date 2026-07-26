# Este paquete se queda vacio a proposito.
#
# `academico` es un espejo de solo lectura del esquema del colegio. En settings
# esta declarada como `MIGRATION_MODULES = {"academico": None}` y el router
# (`config.db_router.TenantRouter`) devuelve False en `allow_migrate` para esta
# app y para cualquier alias `colegio_*`. Aqui nunca debe aparecer un archivo de
# migracion.
