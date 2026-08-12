# Cambios pendientes (producto / arquitectura)

Notas de conversación. Actualizado 2026-07-30.

**Producción JP (cutover, APK, SSL detrás de Caddy):** ya operativos — ver
[`estado-produccion.md`](estado-produccion.md). Lo de abajo es producto / SIE,
no deuda del cutover.

---

## 1. Teléfonos N:M (varios números por estudiante y viceversa)

**Hecho (parcial, pragmatico).** El directorio ahora proyecta **todos** los
números válidos de `estudiantes.telefono_contacto` cuando vienen separados
(`987… / 999…`). Un estudiante → varios teléfonos en `asis_directorio`; un
teléfono → varios estudiantes (filas distintas). Código:
`extraer_telefonos_e164` + `directorio/repositorio.py`.

**Pendiente (modelo limpio).** Alimentar el directorio desde `padres_estudiantes`
(+ teléfono en `usuarios` o tabla `asis_*`), no solo del campo libre del
estudiante. Sin alterar RLS/RPCs legado salvo aditivos `asis_*`.

---

## 2. SIE web → backend del canal (entradas, salidas, incidencias)

**Hecho en el canal.** `POST /v0.1/ingesta/eventos` documentado para Jean Piaget
en [`api-ingesta-sie.md`](api-ingesta-sie.md). Auth: `X-Asiscole-Ingest-Key`.

**Pendiente en el SIE web** (repo asistencias Jean Piaget): tras guardar
entrada/salida/incidencia, llamar a esa API. Guía y ejemplos curl/fetch en el
doc anterior.

Outbox (`asis_outbox` + poller) sigue como respaldo si no se cablea el web.

---

## 3. App: asistencias / incidencias vacías

**Hecho.** Mensaje claro en Asistencias cuando el mes no tiene llegadas/salidas
reales (antes parecía “roto”). Incidencias ya tenían vacío explícito.

**Recordatorio.** Esas pantallas leen la **BD del colegio**. La ingesta solo
llena **Mensajes**. Hace falta registro en SIE + vínculo directorio + estudiante
activo en Perfil.

---

## 4. Hecho en infra / app (2026-07-30) — no pendiente

- Cutover prod: Redis auth, secret rotado, migraciones `0005`/`0002`, RLS `007`.
- `DJANGO_SECURE_SSL_REDIRECT=False` detrás de Caddy (ADR-10).
- App: URL VPS por defecto también en debug; menos falsos “offline” en MIUI.
- APK release: `Asiscole_Messenger.apk` vía `scripts/ops_local_release.ps1`.

## Orden siguiente

1. Cablear SIE JP → `POST /ingesta/eventos` (prioridad).
2. Modelo limpio N:M con `padres_estudiantes` / `asis_*`.
3. Cubits Flutter para asistencias/incidencias + detalle de incidencia (si aún
   faltan frente al OpenAPI).
4. Cuando haya VPS dedicado 32 GB: subir workers a Opción B (estado-produccion §6).
