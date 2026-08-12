# Decisiones de arquitectura (ADR)

Registro corto de las decisiones que no son evidentes al leer el código. Cada una nace de
un conflicto entre el SRS v5 y el esquema real del colegio, o de un riesgo detectado.

---

## ADR-01 — El "DNI del estudiante" es `codigo_barras`

**Contexto.** El SRS pide login con teléfono más DNI del estudiante, pero la tabla
`estudiantes` no tiene columna `dni`. La función existente `buscar_asistencia_por_dni`
compara contra `codigo_barras`.

**Decisión.** El documento que se pide en el login es `estudiantes.codigo_barras`. En la
API el campo se llama `documento_estudiante` para no arrastrar el nombre físico.

**Consecuencia.** Si el colegio empieza a guardar el DNI real en otra columna, solo cambia
el repositorio del directorio.

---

## ADR-02 — El canal no reutiliza `app_sesiones`

**Contexto.** El sistema web ya tiene sesiones en `app_sesiones`, con 15 minutos de vida
para el rol `Padre` y sin `device_id`. El canal móvil necesita 10 días y control de un solo
dispositivo.

**Decisión.** El canal lleva su propio almacén de sesión, `asis_sesion_activa`, en la base
central. `app_sesiones` no se toca.

**Consecuencia.** Un apoderado puede tener sesión en el portal web y en la app a la vez,
porque son sistemas de sesión distintos. Es aceptable: la regla de dispositivo único aplica
al canal móvil.

---

## ADR-03 — Aislamiento en la API, no en RLS

**Contexto.** El esquema del colegio tiene RLS activo, gobernado por `sie_sesion_rol()`,
que lee el header `x-sie-token` a través de PostgREST. Django se conecta por Postgres
directo con un rol de servicio, que evita esas políticas.

**Decisión.** El aislamiento del canal se aplica en la capa de servicios de Django: cada
consulta se filtra por los vínculos del directorio del apoderado autenticado. El RLS
existente se conserva intacto para el sistema web.

**Consecuencia.** Un fallo de autorización en la API expone datos, porque no hay una segunda
red de seguridad en la base. Por eso todo endpoint que reciba un identificador de estudiante
lleva un test de autorización negativa obligatorio.

---

## ADR-04 — Outbox con triggers en lugar de webhooks

**Contexto.** El backend necesita enterarse de cada entrada, salida e incidencia. El sistema
web existente no emite eventos y modificarlo está fuera de alcance.

**Decisión.** Triggers `AFTER` sobre `registros_llegada` e `incidencias` que insertan en
`asis_outbox`, más un poller de Celery que la vacía. La idempotencia se garantiza con
`UNIQUE (tipo, id_registro)` en el outbox y con `UNIQUE (tenant_id, origen_evento)` en
`asis_mensaje`.

**Alternativas descartadas.** Supabase Realtime, por añadir una dependencia de conexión
persistente por colegio. Polling por marca de tiempo, por ser frágil ante relojes y
escrituras retrasadas.

**Consecuencia.** Los triggers nunca pueden abortar la operación del colegio: van envueltos
en un bloque que traga la excepción. Si el outbox falla, se pierde el aviso pero no el
registro de asistencia, que es lo importante.

---

## ADR-05 — Directorio central con caché en Redis

**Contexto.** Resolver un teléfono recorriendo todas las bases de colegio en cada login es
lento y frágil ante caídas parciales.

**Decisión.** Una proyección indexada en la base central, `asis_directorio`, con caché en
Redis por 24 horas. La fuente de verdad sigue siendo la base del colegio.

**Invalidación.** Al cambiar un contacto se actualiza el directorio y se borra la clave de
Redis del teléfono anterior y del nuevo. Un job nocturno reconcilia y corrige derivas.

**Consecuencia.** Si el directorio está poblado, el login no depende de que todas las bases
respondan. Solo se devuelve `503 UPSTREAM_SCHOOL_DB_UNAVAILABLE` cuando el teléfono es
desconocido y no hay forma de resolverlo.

---

## ADR-06 — Denegar el segundo login, con transferencia aprobada

**Contexto.** La sesión única protege la cuenta, pero obligar al apoderado a llamar al
colegio cada vez que cambia de teléfono genera fricción y carga operativa.

**Decisión.** El segundo dispositivo recibe `409` y puede pedir una transferencia. El
dispositivo activo la aprueba o la rechaza mediante un push, con un TTL de cinco minutos y
un máximo de tres solicitudes por hora.

**Consecuencia.** Cubre el caso normal de cambio de equipo sin intervención humana. El
cierre forzado por el administrador queda como vía de escape cuando el apoderado perdió el
dispositivo y no puede aprobar nada.

---

## ADR-07 — Login sin OTP en la versión 1

**Contexto.** Quien conozca el documento de un alumno y el teléfono de su apoderado puede
intentar entrar. El colegio todavía no puede costear el servicio de mensajería para OTP.

**Decisión.** Se acepta el riesgo en la versión 1 y se mitiga con coincidencia estricta,
límite de cinco intentos por cuarto de hora, bloqueo de treinta minutos, sesión única y
aviso push al dispositivo activo ante cualquier intento.

**Consecuencia.** Es una decisión de producto revisable. Cuando haya presupuesto se añade
OTP en el primer login y en la transferencia de dispositivo.

---

## ADR-08 — Prefijo `asis_` para todo lo nuevo

**Contexto.** El prefijo natural habría sido `app_`, pero el sistema web ya lo usa en
`app_sesiones`.

**Decisión.** Todo objeto creado por el canal lleva prefijo `asis_`, tanto en las bases de
colegio como en la central.

---

## ADR-09 — Los estados de asistencia se derivan

**Contexto.** El SRS pide mostrar "falta" y "sin registro", pero `registros_llegada` solo
guarda filas de asistencia efectiva, con estado `A tiempo` o `Tarde`, y es única por
estudiante y fecha.

**Decisión.** La API devuelve el mes completo y deriva los estados ausentes. La app nunca
infiere nada localmente.

**Consecuencia.** Falta definir con el colegio el calendario lectivo para distinguir un día
sin clases de una falta real. Mientras tanto se marca `sin_registro`.

---

## ADR-10 — Sin `SECURE_SSL_REDIRECT` detrás de Caddy/Cloudflare

**Contexto.** Con `DEBUG=False`, Django activaba `SECURE_SSL_REDIRECT` por defecto.
Caddy termina TLS y habla HTTP con Gunicorn en `127.0.0.1:8000`. Si falta
`X-Forwarded-Proto` (o el redirect se arma con el path ya strippeado), Django
responde 301 a `https://host/v0.1/...` **sin** `/canal-api`. El cliente sigue el
redirect y recibe el HTML del SIE.

**Decisión.** En producción detrás de proxy: `DJANGO_SECURE_SSL_REDIRECT=False`.
Caddy/Cloudflare ya fuerzan HTTPS. El default en código es `False`.

**Consecuencia.** No depender del redirect de Django para TLS. Documentado en
[`estado-produccion.md`](estado-produccion.md) (incidente 2026-07-30).

---

## ADR-11 — App: VPS por defecto también en debug

**Contexto.** El default `http://10.0.2.2:8000` solo sirve al emulador Android.
Las pruebas reales son en celular físico contra el VPS.

**Decisión.** `Env.baseUrl` apunta a producción salvo
`--dart-define=ASISCOLE_ENV=dev` o `API_BASE_URL=...`.

**Consecuencia.** Un `flutter run` en dispositivo habla al canal real; el
desarrollo local exige `-Local` / define explícito.
