# Migraciones SQL del canal apoderado

Scripts SQL del canal Asiscole. Hay **dos bases de datos distintas** en juego y cada
script va en una de ellas; ejecutarlos en la que no toca no funciona.

| Script | Dónde se ejecuta | Cuándo |
| --- | --- | --- |
| `001_colegio_outbox.sql` | Cada **BD de colegio** (Supabase, una por colegio) | Una vez por colegio, al incorporarlo al canal |
| `002_central_schema.sql` | **BD central** del canal (PostgreSQL propio) | Una sola vez, al levantar el entorno |
| `003_seeds_desarrollo.sql` | BD de colegio **local** | Solo en desarrollo, nunca en producción |
| `004_mensaje_unico_por_apoderado.sql` | **BD central** (si ya aplicaste un `002` antiguo) | Corrige el índice único de mensajes |
| `005_central_gaps.sql` | **BD central** (si ya aplicaste un `002` antiguo) | Añade estudiante activo y cursor de ingesta |
| `006_confirmacion_incidencia.sql` | **BD central** (si ya aplicaste un `002` antiguo) | Confirmación de incidencias + flag `citacion` |

`db/legacy/bootstrap_colegio.sql` es solo referencia estructural del esquema del
colegio: no se ejecuta y no se edita.

## Orden de ejecución

1. `002_central_schema.sql` en la BD central (o, en producción, las migraciones de
   Django, que son las dueñas del esquema).
2. `001_colegio_outbox.sql` en la BD de cada colegio.
3. `003_seeds_desarrollo.sql` solo si se está montando un colegio de prueba local,
   siempre después de `001` para que los triggers dejen filas en `asis_outbox`.

Los pasos 1 y 2 son independientes entre sí; el orden entre ellos da igual.

## Qué hace cada script

### `001_colegio_outbox.sql` — BD de colegio

Crea el patrón *outbox* que avisa al backend de eventos nuevos:

- `public.asis_outbox`: cola de eventos con `UNIQUE (tipo, id_registro)` e índice
  parcial sobre los pendientes.
- `public.asis_fn_encolar_evento()`: trigger `AFTER` genérico que arma el payload
  completo (datos del estudiante, de la falta y del usuario que reportó) para que
  Django no tenga que volver a consultar el esquema del colegio.
- Tres triggers: `asis_trg_llegada_entrada` (INSERT en `registros_llegada`),
  `asis_trg_llegada_salida` (UPDATE que rellena `hora_salida`) y
  `asis_trg_incidencia` (INSERT de incidencia con `estado = 'Activa'`).
- `asis_idx_estudiantes_tel_norm`: índice funcional sobre el teléfono normalizado a
  dígitos, para el login.
- `public.asis_v_directorio_origen`: vista origen del directorio central.

Los triggers nunca abortan la operación del colegio: si el encolado falla, se traga
el error y el registro de asistencia o la incidencia se guardan igual.

### `002_central_schema.sql` — BD central

Referencia canónica del modelo del canal: cuentas de apoderado, directorio
teléfono ↔ estudiante ↔ colegio, sesión única por dispositivo, transferencia de
sesión, tokens push, bandeja de mensajes, intentos de login, feature flags y
auditoría.

**Django es el dueño de este esquema.** En producción las tablas las crean y
evolucionan las migraciones de Django. Este archivo sirve para levantar la base a
mano y para revisar el modelo de un vistazo. Si ambos divergen, gana Django y este
archivo se actualiza en el mismo PR.

### `003_seeds_desarrollo.sql` — solo desarrollo

Un usuario Tutor, tres estudiantes con teléfonos peruanos escritos en tres formatos
distintos (para probar la normalización a E.164), dos faltas de catálogo, registros
de llegada, una salida y una incidencia activa. Nombres, códigos y teléfonos son
ficticios.

## Cómo aplicarlos con psql

Los scripts van envueltos en una transacción; si algo falla no queda nada a medias.
Se necesita un rol con permisos DDL sobre `public` (el `postgres` del proyecto o el
owner del esquema), no la `anon key`.

BD de colegio (Supabase, conexión directa):

```bash
psql "postgresql://postgres:CLAVE@db.PROJECT_REF.supabase.co:5432/postgres" \
  -v ON_ERROR_STOP=1 -f db/migrations/001_colegio_outbox.sql
```

BD central del canal:

```bash
psql "postgresql://USUARIO:CLAVE@HOST:5432/asiscole_central" \
  -v ON_ERROR_STOP=1 -f db/migrations/002_central_schema.sql
```

Seeds en un colegio local:

```bash
psql "postgresql://postgres:postgres@localhost:5432/colegio_demo" \
  -v ON_ERROR_STOP=1 -f db/migrations/003_seeds_desarrollo.sql
```

En PowerShell la sintaxis es la misma; solo cambia el carácter de continuación de
línea (usar acento grave `` ` `` en vez de `\`, o escribir todo en una sola línea).

## Alta de un colegio nuevo

`001_colegio_outbox.sql` **se ejecuta una vez por cada colegio que se incorpora al
canal**. No es un script global: cada colegio tiene su propia base Supabase y, por
tanto, su propio `asis_outbox` y sus propios triggers. El checklist del alta es:

1. Aplicar `001_colegio_outbox.sql` en la BD del colegio nuevo.
2. Dar de alta el `tenant_id` y las credenciales del rol de servicio en la
   configuración de Django.
3. Verificar que el poller ve la cola: `SELECT count(*) FROM public.asis_outbox;`
4. Lanzar la sincronización del directorio desde
   `public.asis_v_directorio_origen` hacia `asis_directorio` de la BD central.

## Reejecución e idempotencia

Todos los scripts se pueden ejecutar dos veces sin fallar: `CREATE ... IF NOT
EXISTS`, `CREATE OR REPLACE`, `DROP TRIGGER IF EXISTS` antes de cada `CREATE
TRIGGER`, `ON CONFLICT DO NOTHING` e `INSERT ... WHERE NOT EXISTS` en los seeds.

Volver a ejecutar `001` recrea función y triggers pero no toca los datos ya
encolados. Lo que **no** se hace nunca es `ALTER` o `DROP` sobre tablas, funciones
`sie_*`, triggers, RLS o GRANTs del esquema legado.

## Requisitos y supuestos

- PostgreSQL 15 o superior en la BD de colegio: la vista usa
  `security_invoker = true`.
- La extensión `pgcrypto` en el esquema `extensions` de la BD de colegio (ya viene
  con el bootstrap); los seeds la usan para hashear la contraseña de prueba.
- El backend se conecta con un **rol de servicio** que evita RLS. No se otorga nada
  nuevo a `anon` ni a `authenticated`; de hecho `001` les revoca el acceso a los
  objetos nuevos.

## Privacidad (Ley N.º 29733)

- El payload de `asis_outbox` **no** lleva `telefono_contacto` ni `codigo_barras`:
  Django resuelve el destinatario con `(tenant_id, id_estudiante)` contra su
  directorio.
- `asis_intento_login.clave` guarda un **hash** de teléfono + código, nunca el dato
  en claro.
- Los mensajes se purgan o anonimizan a los 24 meses (`asis_mensaje.retenido_hasta`).
- Ni los triggers ni la auditoría escriben nombres, teléfonos, códigos de barras o
  contenido de mensajes en los logs.
