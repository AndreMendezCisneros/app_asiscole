# Despliegue del backend del canal (VPS)

Guía operativa para **actualizar** el VPS actual o **montar uno nuevo** sin
repetir los fallos típicos (FCM simulado, Supabase IPv6, migraciones, secretos).

Arquitectura resumida:

```text
SIE / BD colegio (Supabase por tenant)
  → asis_outbox (+ triggers)  ó  POST /ingesta/eventos
       ↓
Canal Django (VPS) + Redis + Celery worker/beat
  → BD central del canal (otro Supabase)
  → FCM Admin → app Asis Messenger
       ↓
Caddy/nginx (TLS) → 127.0.0.1:8000  bajo  /canal-api
```

**Estado vivo del despliegue JP (qué ya se aplicó, APK, incidentes):**  
[`estado-produccion.md`](estado-produccion.md).

**Regla de alineación:** producción (VPS) es la fuente principal. Ante
divergencias, el código/config del servidor manda sobre el working copy local,
salvo un deploy intencional desde el repo.

Referencias relacionadas:

- Compose: [`docker-compose.prod.yml`](../docker-compose.prod.yml)
- Variables prod: [`.env.production.example`](../.env.production.example) (no usar `.env.example` de dev)
- SQL colegio / central: [`db/migrations/README.md`](../db/migrations/README.md)
- Push: [`docs/diagnostico-push.md`](diagnostico-push.md)
- Script FCM: [`scripts/deploy_push_fcm_vps.sh`](../scripts/deploy_push_fcm_vps.sh)
- Load smoke: [`scripts/load/k6_canal_100vu.js`](../scripts/load/k6_canal_100vu.js)

---

## 0. Hardware recomendado (Hetzner dedicado — Opción B)

**Hoy (JP):** el canal comparte un Cloud ~4 vCPU / 8 GB con SIE; workers
bajados a 3×2 / Celery 2. Detalle vivo: [`estado-produccion.md`](estado-produccion.md).

Perfil objetivo para **miles de apoderados activos** (pico matutino), con BD en
Supabase (el VPS no hospeda Postgres del canal):

| Recurso | Objetivo |
| --- | --- |
| CPU | 8–12 núcleos (AMD reciente / AX o equivalente en [Server Auction](https://www.hetzner.com/sb/)) |
| RAM | **32 GB** |
| Disco | ≥ 256 GB NVMe/SSD |
| Red | 1 Gbit (incluido) |
| Rol | Solo canal (Caddy + Gunicorn + Celery + Redis). **No** mezclar con SIE. |

Defaults de capacidad en `docker-compose.prod.yml` / `.env.production.example`:

| Parámetro | Valor Opción B | Efecto |
| --- | --- | --- |
| `GUNICORN_WORKERS` × `GUNICORN_THREADS` | 8 × 4 | ≈ 32 requests HTTP en paralelo |
| `CELERY_CONCURRENCY` | 6 | Push / outbox / purga |
| Redis `maxmemory` | 2 GB (LRU) | No come la RAM de la API |

Tras el alta: `docker compose … up -d --build`, migraciones, health, y smoke k6
en ventana controlada (500 → 1000 VU) midiendo p95 bajo 800 ms.

---

## 1. Qué va en el servidor y qué no

| Elemento | ¿En el VPS? | ¿En Git? | Notas |
| --- | --- | --- | --- |
| Código `backend/` + compose | Sí | Sí | `git pull` o tar de deploy |
| `.env` de producción | Sí | **No** | Partir de `.env.production.example` |
| `secrets/fcm-adminsdk.json` | Sí | **No** | Firebase **Admin**, no el de la app |
| `google-services.json` / `firebase_options.dart` | No (solo app) | Stub / privado | Claves de **cliente** |
| BD central Supabase | Externa | No | Proyecto propio del canal |
| BD de cada colegio | Externa | No | Via `SCHOOL_DATABASES` |
| Redis (volumen Docker) | Sí | No | Cola Celery + caché |
| Caddy / certificados | Sí | No | TLS delante de gunicorn |

**Nunca** copiar al APK ni a Git: Admin SDK, `DJANGO_SECRET_KEY`, passwords de
Supabase, `INGEST_API_KEY`.

---

## 2. Actualizar el VPS que ya existe

Ruta típica hoy: `/opt/asiscole-canal` (Jean Piaget).

### 2.1 Checklist previo

- [ ] Backup mental: `.env` y `secrets/` no se borran ni se pisan con el tar.
- [ ] Health actual responde: `curl -sS https://DOMINIO/canal-api/health`
- [ ] Sabes si hay migraciones Django nuevas en el PR/commit.

### 2.2 Procedimiento (cutover)

```bash
cd /opt/asiscole-canal
git pull origin master   # o desplegar tar con el código nuevo

# .env alineado a .env.production.example:
#   DJANGO_DEBUG=False, DJANGO_SECRET_KEY ≥32 chars,
#   DJANGO_SECURE_SSL_REDIRECT=False   ← OBLIGATORIO detrás de Caddy
#   REDIS_PASSWORD + REDIS_URL=redis://:PASSWORD@redis:6379/0
#   En host ~8 GB: bajar GUNICORN_WORKERS/THREADS y CELERY_CONCURRENCY
#   (ver estado-produccion.md; no dejar 8×4 en máquina pequeña)

test -f secrets/fcm-adminsdk.json
bash scripts/ops_prod_cutover.sh
```

El script valida `.env`, hace `build`/`up` (Redis auth), `migrate` (p. ej.
`0005_transferencia_token_consulta` + índice directorio) y aplica
`db/migrations/007_central_rls_lockdown.sql` en la BD central.

**Rotar `DJANGO_SECRET_KEY` invalida todas las sesiones:** los apoderados deben
volver a iniciar sesión (borrar datos de la app si el APK viejo queda pegado).

Verificación manual:

```bash
curl -sS http://127.0.0.1:8000/health
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs --tail=50 worker
```

APK en tu PC: `.\scripts\ops_local_release.ps1` (genera `Asis_Messenger.apk`).

### 2.3 Qué NO tocar en un update

- `.env` (salvo variables nuevas documentadas en `.env.example`)
- `secrets/`
- Volumen `canal_redis_data`
- Config de Caddy / DNS

---

## 3. Desplegar en un VPS nuevo (desde cero)

### 3.1 Requisitos del host

- Ubuntu/Debian reciente, Docker + Compose plugin
- Dominio apuntando al VPS (A/AAAA)
- Caddy o nginx para TLS
- Acceso SSH
- Proyectos Supabase: **uno central del canal** + **uno por colegio**

### 3.2 Layout recomendado

```text
/opt/asiscole-canal/
  docker-compose.prod.yml   # o enlace al del repo
  backend/                  # código Django
  .env                      # secretos (chmod 600)
  secrets/
    fcm-adminsdk.json       # Firebase Admin
```

### 3.3 Pasos

#### A. Código

```bash
sudo mkdir -p /opt/asiscole-canal/secrets
cd /opt/asiscole-canal
git clone https://github.com/AndreMendezCisneros/app_asiscole.git .
# o copiar solo lo necesario: backend/, docker-compose.prod.yml, scripts/
```

#### B. `.env`

```bash
cp .env.production.example .env
chmod 600 .env
nano .env   # completar (ver sección 4)
```

Mínimo obligatorio en producción:

| Variable | Valor orientativo |
| --- | --- |
| `DJANGO_SECRET_KEY` | Aleatorio ≥32 chars (el arranque aborta si es el default) |
| `DJANGO_DEBUG` | `False` (plantilla: `.env.production.example`) |
| `DJANGO_SECURE_SSL_REDIRECT` | **`False`** detrás de Caddy/Cloudflare (ADR-10) |
| `DJANGO_ALLOWED_HOSTS` | `tu.dominio.com,127.0.0.1` |
| `CENTRAL_DB_*` | Proyecto Supabase **del canal** (pooler IPv4) |
| `CENTRAL_DB_SSLMODE` | `require` |
| `SCHOOL_DATABASES` | JSON del/los colegios (pooler) |
| `REDIS_PASSWORD` | Obligatoria (Compose la pasa a `redis-server --requirepass`) |
| `REDIS_URL` | `redis://:PASSWORD@redis:6379/0` (desde `.env`, no se sobrescribe) |
| `GUNICORN_WORKERS` / `THREADS` | `8` / `4` (Opción B; ver sección 0) |
| `CELERY_CONCURRENCY` | `6` |
| `USE_LOCMEM_CACHE` | `False` |
| `POLL_OUTBOX_INLINE` | `False` |
| `FCM_CREDENTIALS_PATH` | `/secrets/fcm-adminsdk.json` |
| `INGEST_API_KEY` | Clave fuerte (SIE → canal) |

Tras crear la BD central en Supabase: aplicar
`db/migrations/007_central_rls_lockdown.sql` **o** desactivar la Data API del
proyecto (PostgREST). Django usa rol de servicio / BYPASSRLS.

#### C. Secrets FCM

```bash
# Mismo proyecto Firebase que google-services.json de la app
cp /ruta/segura/asiscole-*-firebase-adminsdk-*.json \
   /opt/asiscole-canal/secrets/fcm-adminsdk.json
chmod 600 /opt/asiscole-canal/secrets/fcm-adminsdk.json
```

#### D. Contenedores

```bash
cd /opt/asiscole-canal
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml exec backend \
  python manage.py migrate --noinput
```

Servicios esperados: `asiscole_canal_redis`, `_backend`, `_worker`, `_beat`.

#### E. Reverse proxy (Caddy ejemplo)

```caddyfile
tu.dominio.com {
    handle_path /canal-api/* {
        reverse_proxy 127.0.0.1:8000
    }
}
```

Ajusta el `handle`/`strip_prefix` según cómo Caddy entregue el path. Health
público:

```text
https://tu.dominio.com/canal-api/health
```

#### F. BD de cada colegio

En **cada** Supabase de colegio (SQL Editor o `psql`), una vez:

```bash
psql "postgresql://..." -v ON_ERROR_STOP=1 \
  -f db/migrations/001_colegio_outbox.sql
```

Sin esto no hay `asis_outbox` ni triggers → no llegan entradas/salidas/incidencias.

#### G. App móvil

- Release apunta por defecto a Jean Piaget; para otro dominio:
  ```powershell
  flutter build apk --release `
    --dart-define=API_BASE_URL=https://tu.dominio.com/canal-api/v0.1
  ```
- `firebase_options.dart` / `google-services.json` del **mismo** proyecto Firebase
  que el Admin del VPS (copiados desde canal privado / `secrets/`, no desde Git).

---

## 4. `SCHOOL_DATABASES` y pooler (crítico en VPS sin IPv6)

Muchos VPS **no tienen IPv6**. El host `db.<ref>.supabase.co` suele ser solo AAAA
→ timeouts y el mensaje de app *“no pudimos conectarnos con el sistema del colegio”*.

Usar el **pooler** Session/Transaction:

```json
[
  {
    "tenant_id": "jean_piaget",
    "nombre": "Jean Piaget",
    "host": "aws-1-us-west-2.pooler.supabase.com",
    "port": 6543,
    "name": "postgres",
    "user": "postgres.PROJECT_REF",
    "password": "CLAVE",
    "sslmode": "require"
  }
]
```

En una sola línea en `.env`:

```bash
SCHOOL_DATABASES=[{"tenant_id":"jean_piaget",...}]
```

Si la password contiene `$`, en archivos leídos por Compose duplicar: `$$`.

---

## 5. Migraciones

| Origen | Dónde | Quién |
| --- | --- | --- |
| `python manage.py migrate` | BD **central** | Django (fuente de verdad) |
| `001_colegio_outbox.sql` | BD **colegio** | Una vez por tenant |
| `002`…`006` SQL | Solo referencia / entornos viejos | Preferir migrate Django en prod |

Tras features nuevas (p. ej. confirmación de incidencias), **siempre** `migrate`
en el contenedor `backend` después del rebuild.

---

## 6. Verificación post-deploy

```bash
# Health (local y público)
curl -sS http://127.0.0.1:8000/health
curl -sS https://DOMINIO/canal-api/health
# → status ok + fcm_disponible true

# Contenedores
docker compose -f docker-compose.prod.yml ps

# Worker: sin push_simulado; beat activo
docker compose -f docker-compose.prod.yml logs --tail=100 worker beat

# App
# 1) Login → PUT /perfil/push-token 204
# 2) Incidencia/entrada en SIE → mensaje en bandeja + shade (app en Home)
# 3) Marca de hora en America/Lima (no +5 h fantasma)
```

---

## 7. Errores frecuentes

| Síntoma | Causa probable | Acción |
| --- | --- | --- |
| Health sin `fcm_disponible` | Código viejo en contenedor | Rebuild con `requirements` + `urls.py` actuales |
| `fcm_disponible: false` / `push_simulado` | Falta JSON Admin o path mal | `secrets/fcm-adminsdk.json` + env |
| Mensajes en app, sin shade | FCM off o MIUI; o payload viejo | Ver `diagnostico-push.md`; data-only + handler BG |
| “No conectamos con el colegio” | Host IPv6 / password / JSON `SCHOOL_DATABASES` | Pooler + validar JSON |
| 404 en confirmar incidencia | Backend sin deploy de la feature | Pull + migrate + rebuild |
| Login 500 | Migraciones central pendientes | `manage.py migrate` |
| “Sin conexión” / login 200 con ~5 KB y sin bandeja | `SECURE_SSL_REDIRECT=True` → HTML del SIE | `.env`: `DJANGO_SECURE_SSL_REDIRECT=False` + recreate backend (ADR-10) |
| APK viejo deja de entrar tras cutover | Secret JWT rotado | Borrar datos app + login de nuevo |
| Ingesta 401 | `INGEST_API_KEY` distinta en SIE y canal | Alinear claves |
| Solo backend, sin avisos nuevos | Worker/beat caídos | `up -d worker beat` |
| OOM / latencia en VPS 8 GB | Workers Opción B (8×4) en host chico | Bajar a 3×2 / Celery 2 (estado-produccion) |

---

## 8. Mismo canal vs otro colegio

| Pregunta | Recomendación |
| --- | --- |
| ¿Solo actualizar código JP? | Sección 2 (mismo VPS, mismo `.env`) |
| ¿Otro VPS, mismo producto/app? | Sección 3; **mismo** Firebase; BD central nueva o compartida según producto |
| ¿Otro colegio en el **mismo** canal? | Añadir entrada a `SCHOOL_DATABASES` + `001_outbox` en esa BD; rebuild no obligatorio si solo cambia `.env` (sí restart backend/worker) |
| ¿Separar por completo? | VPS + BD central + `.env` + dominio propios; app con otro `API_BASE_URL` |

---

## 9. Seguridad operativa

- `.env` y `secrets/` con `chmod 600`, dueño root o usuario de deploy.
- No imprimir passwords, tokens FCM ni PII en logs (Ley 29733).
- Restringir API keys de Firebase cliente (Android package + SHA-1) en Google Cloud.
- Rotar `INGEST_API_KEY` y `DJANGO_SECRET_KEY` si se filtran.
- El APK puede contener claves **cliente** Firebase; eso no equivale al Admin SDK.

---

## 10. Comando rápido (ops)

Actualizar push + backend en el VPS ya configurado:

```bash
bash scripts/deploy_push_fcm_vps.sh
# o el bloque de la sección 2.2
```

Sonda única:

```powershell
Invoke-RestMethod https://jeanpiaget.asiscole.com/canal-api/health
```
