# Estado de producción — Canal Asiscole Messenger

Actualizado: **2026-08-13**.

Documento de verdad operativa: qué está desplegado, qué APK distribuir y qué
lecciones no repetir. Complementa [`deploy-vps.md`](deploy-vps.md).

**Prioridad:** lo que corre en **producción (VPS)** es la fuente principal.
Si local y prod divergen, se alinea el repo/local hacia prod (salvo un cambio
local explícito que se vaya a desplegar a propósito).

---

## 1. Despliegue actual (Jean Piaget)

| Pieza | Valor |
| --- | --- |
| Dominio API | `https://jeanpiaget.asiscole.com/canal-api` |
| Health | `https://jeanpiaget.asiscole.com/canal-api/health` |
| Host VPS | Hetzner Cloud **compartido** con SIE JP (`/opt/asiscole-canal`) |
| Capacidad actual | ~4 vCPU / ~8 GB RAM (no es Opción B dedicada) |
| Compose | `docker-compose.prod.yml` |
| Workers actuales | Gunicorn **3×2**, Celery **2**, Redis maxmemory **256mb** (ajustado al host 8 GB) |
| BD central | Supabase proyecto **Asiscole** (canal) |
| BD colegio | Supabase Jean Piaget vía `SCHOOL_DATABASES` (pooler IPv4) |
| Push | FCM Admin en `secrets/fcm-adminsdk.json` → health `fcm_disponible: true` |
| Proxy | Caddy `sites.d/10-jeanpiaget.caddy` → `strip_prefix /canal-api` → `:8000` |

Swagger (`/v0.1/docs/`) **no** se sirve con `DJANGO_DEBUG=False`.

---

## 2. Cutover 2026-07-30 (ya aplicado)

1. Compose prod + Redis con contraseña (`REDIS_PASSWORD` / `REDIS_URL`).
2. `DJANGO_DEBUG=False` y `DJANGO_SECRET_KEY` rotado (≥32 chars) → **todas las
   sesiones JWT anteriores quedaron inválidas** (hay que volver a iniciar sesión).
3. Migraciones Django en BD central:
   - `cuentas.0005_transferencia_token_consulta`
   - `directorio.0002_idx_tenant_estudiante`
   - (previas: confirmación incidencia, términos, etc.)
4. RLS lockdown: `db/migrations/007_central_rls_lockdown.sql` en la BD central.
5. Capacidad bajada al hardware real (sección 1), no a los defaults Opción B del
   compose (8×4 / Celery 6), que son para VPS dedicado 32 GB.

Verificación Supabase Table Editor: `django_migrations` debe listar `0005` y
`0002_idx_tenant_estudiante`. `RLS disabled` en tablas `django_*` es normal;
las tablas `asis_*` son las del canal.

---

## 3. Incidente: “Sin conexión a internet” tras cutover

### Síntoma

App (debug y APK viejo) mostraba “Sin conexión…” aunque el teléfono tenía datos.
A veces el log decía `POST /auth/login -> 200` con ~5 KB de respuesta, pero la
sesión no entraba bien.

### Causa

Con `DJANGO_DEBUG=False` el default era `DJANGO_SECURE_SSL_REDIRECT=True`.
Django, al no ver TLS (Caddy → HTTP a `:8000`), respondía **301** a
`https://host/v0.1/...` **sin** el prefijo `/canal-api`. El cliente seguía el
redirect y recibía el HTML del SIE (SPA), no el JSON del canal.

### Remedio (aplicado en VPS)

```bash
# En /opt/asiscole-canal/.env
DJANGO_SECURE_SSL_REDIRECT=False
docker compose -f docker-compose.prod.yml up -d --force-recreate backend worker beat
```

En código: default de `SECURE_SSL_REDIRECT` es `False` detrás de proxy
([`backend/config/settings.py`](../backend/config/settings.py)); plantilla
[`.env.production.example`](../.env.production.example).

### Cómo distinguir respuesta buena vs mala

| Login OK (canal) | Login engañoso (SIE HTML) |
| --- | --- |
| `POST /auth/login -> 200` | También puede verse `200` |
| ~500–800 bytes típicos | ~5 KB+ de HTML |
| Luego `GET /mensajes`, `/perfil` 200 | No hay más llamadas JSON útiles |

---

## 4. App móvil

### API por defecto

Debug y release apuntan al VPS:

`https://jeanpiaget.asiscole.com/canal-api/v0.1`

(`frontend/mobile/lib/core/config/env.dart`).  
`10.0.2.2` solo con `--dart-define=ASISCOLE_ENV=dev` (emulador).

### APK de distribución

```powershell
# Desde la raíz del repo
.\scripts\ops_local_release.ps1
# o: cd frontend/mobile; .\tool\build_apk.ps1
```

Artefacto:

`frontend/mobile/build/app/outputs/flutter-apk/Asis_Messenger.apk`

(~51 MB; último build local 2026-07-30). Incluye ofuscación Dart + R8, Firebase
desde `secrets/`. Sin `android/key.properties` se firma con clave de debug
(pruebas / sideload).

### Tras rotar `DJANGO_SECRET_KEY`

Los apoderados con APK/sesión antigua deben **cerrar sesión o borrar datos de la
app** e iniciar sesión de nuevo. No basta con reinstalar encima si queda el
Keystore local.

### Robustez post-incidente (código app)

- No bajar a “offline” solo por `connectivity_plus` (falsos negativos en MIUI).
- Login concurrente: un 200 no lo pisa un fallo posterior.
- Tras `OnlineSync` / `OfflineMessagesOnly`, navegación forzada a Mensajes.

---

## 5. Checklist rápido post-deploy

```bash
curl -sS https://jeanpiaget.asiscole.com/canal-api/health
# → status ok, fcm_disponible true

# En el VPS
cd /opt/asiscole-canal
grep DJANGO_SECURE_SSL_REDIRECT .env   # debe ser False
docker compose -f docker-compose.prod.yml ps
```

En la app: login → bandeja → `PUT /perfil/push-token` 204 → avisos FCM.

---

## 6. Colegios conectados

El canal habla con **BD central + N BDs de colegio** (`SCHOOL_DATABASES`).

| tenant_id | Notas |
| --- | --- |
| `jean_piaget` | Outbox + ingesta HTTP; referencia estable |
| `asis_academy` | Ingesta HTTP vía `demostracion.asisacademy.com/canal-api`. Un `202` con `creados: 0` significa sin destinatario en directorio, no fallo de red. |

Ingesta acepta `entrada` \| `salida` \| `incidencia` \| `aviso`.

Tras este trabajo hay que aplicar en la central `administracion.0003_semilla_version_app`
(`manage.py migrate`) y, si se opera por SQL, [`db/migrations/008_central_app_version.sql`](../db/migrations/008_central_app_version.sql).
La app pasa a `1.0.1+2`. `min_soportada` se deja en **1** a propósito: los APK
ya repartidos siguen funcionando.

---

## 7. Precondiciones de red (no romper el rate-limit)

Caddy es hoy el **único** proxy de confianza. El canal toma la IP de origen del
**último** salto de `X-Forwarded-For` (`apps.cuentas.views._ip_de` /
`apps.common.red.ip_de`). Eso es correcto con un hop.

Si se pone **Cloudflare** (u otro CDN) delante de Caddy, el último salto pasa a
ser la IP del edge, compartida por todos los apoderados: tres fallos de login de
cualquiera bloquearían a todos. En ese caso hay que leer `CF-Connecting-IP` (o
configurar el número de hops de confianza) **antes** de activar el proxy. No es
un cambio de código que se pueda dejar para después: el rate-limit se volvería
global sin ningún aviso.

La carga contra este host se mide con `scripts/load/k6_canal_100vu.js` (40 VU,
p95 &lt; 1,5 s). El script de 1000 VU es solo para la Opción B.

---

## 8. Hardware futuro (Opción B)

Cuando haya VPS dedicado ~8 CPU / 32 GB: subir en `.env` a los defaults del
compose (`GUNICORN_WORKERS=8`, `THREADS=4`, `CELERY_CONCURRENCY=6`, Redis 2 GB)
y **no** mezclar con SIE en el mismo host. Detalle: [`deploy-vps.md`](deploy-vps.md) §0.

---

## 9. Documentación relacionada

| Doc | Contenido |
| --- | --- |
| [`deploy-vps.md`](deploy-vps.md) | Procedimiento cutover / VPS nuevo |
| [`diagnostico-push.md`](diagnostico-push.md) | FCM / MIUI |
| [`api-ingesta-sie.md`](api-ingesta-sie.md) | SIE → canal |
| [`ADR.md`](ADR.md) | Decisiones (incl. SSL detrás de proxy) |
| [`../frontend/mobile/README.md`](../frontend/mobile/README.md) | App Flutter / APK |
| [`../.env.production.example`](../.env.production.example) | Variables prod |
