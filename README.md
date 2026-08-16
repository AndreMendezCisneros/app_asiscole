# Asiscole Messenger — Canal de notificación al apoderado

Monorepo del canal móvil de Asiscole: reemplaza WhatsApp como medio de comunicación entre el
colegio y el apoderado, sobre el sistema escolar Asiscole ya existente (una base de datos
Supabase/PostgreSQL por colegio).

Documento fuente de requerimientos: [docs/Asiscole_SRS_v5.docx](docs/Asiscole_SRS_v5.docx).

## Estructura

```
backend/    Django 5 + DRF + Celery — API del canal, ingesta y push
frontend/
  mobile/     Flutter — app del apoderado (mensajes, asistencias, incidencias, notas, perfil)
db/
  legacy/     Esquema real del colegio, solo como referencia (NO ejecutar)
  migrations/ SQL aditivo del canal (prefijo asis_)
docs/       SRS, OpenAPI, ADRs
```

## Conceptos clave

El sistema escolar ya existe y no se modifica. El canal añade tablas con prefijo `asis_`
y descubre los eventos nuevos mediante un outbox alimentado por triggers.

- La **BD central del canal** es un Postgres propio (en la práctica un **proyecto
  Supabase dedicado** al canal). Ahí viven cuentas, sesiones, mensajes y directorio.
- Cada **colegio** sigue en su propio Supabase Asiscole; el canal solo se conecta
  en lectura y aplica `001_colegio_outbox.sql` ahí.
- El "DNI del estudiante" que se pide en el login es `estudiantes.codigo_barras`.
- El teléfono del apoderado es `estudiantes.telefono_contacto`, normalizado a E.164 en el directorio.
- El aislamiento de datos del canal se aplica en la capa de API de Django, no en RLS.

## Puesta en marcha

Requisitos: Python 3.12, Flutter 3.x, Redis (Docker basta), y un **proyecto Supabase
propio** para la BD central del canal (distinto de las BD de cada colegio).

### 1. BD central en Supabase

1. Crea un proyecto nuevo (ej. `asiscole-canal`). No reutilices el de un colegio.
2. En *Project Settings → Database* copia host, user, password y puerto.
3. Copia `.env.example` a `.env` y rellena `CENTRAL_DB_*` + `CENTRAL_DB_SSLMODE=require`.

### 2. Redis + backend

```bash
cp .env.example .env   # y editar CENTRAL_DB_* hacia tu Supabase del canal
docker compose up -d redis
cd backend
python -m venv .venv && .venv/Scripts/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

`docker compose up -d postgres` solo hace falta si prefieres la BD central en local
en vez de Supabase.

Worker y scheduler de Celery, en terminales aparte:

```bash
celery -A config worker -l info
celery -A config beat -l info
```

App móvil:

```bash
cd frontend/mobile
flutter pub get
flutter run
```

## Documentación

- [docs/estado-produccion.md](docs/estado-produccion.md) — **qué está en prod ahora**
  (VPS, migraciones, APK, incidente SSL).
- [docs/deploy-vps.md](docs/deploy-vps.md) — cutover / VPS nuevo.
- [docs/openapi.yaml](docs/openapi.yaml) — contrato de API `/v0.1/` (contract-first).
- [frontend/mobile/README.md](frontend/mobile/README.md) — app Flutter y APK.
- [docs/ADR.md](docs/ADR.md) — decisiones de arquitectura.
- [db/migrations](db/migrations) — SQL aditivo del canal (`asis_*`).

## Producción (VPS Jean Piaget)

**Estado operativo actual (cutover, APK, incidentes):**  
[`docs/estado-produccion.md`](docs/estado-produccion.md).

El backend del canal corre en el mismo VPS que SIE JP, detrás de Caddy:

| Recurso | URL |
| --- | --- |
| Health | https://jeanpiaget.asiscole.com/canal-api/health |
| API | https://jeanpiaget.asiscole.com/canal-api/v0.1/… |
| Ingesta (SIE → canal) | `POST …/canal-api/v0.1/ingesta/eventos` |

Swagger (`/v0.1/docs/`) solo con `DJANGO_DEBUG=True` (no en producción).

Compose: `docker-compose.prod.yml`. Defaults del archivo asumen **Opción B**
(~8 CPU / 32 GB); el host actual es más pequeño y va **downscaleado** (ver
estado-produccion). Variables: [`.env.production.example`](.env.production.example).

**Obligatorio detrás de Caddy:** `DJANGO_SECURE_SSL_REDIRECT=False` (si es `True`,
la app recibe HTML del SIE y muestra “sin conexión”).

La app Flutter (debug y release) usa por defecto
`https://jeanpiaget.asiscole.com/canal-api/v0.1`
(`frontend/mobile/lib/core/config/env.dart`).

APK de distribución:

```powershell
.\scripts\ops_local_release.ps1
# → frontend/mobile/build/app/outputs/flutter-apk/Asis_Messenger.apk
```

Despliegue: [docs/deploy-vps.md](docs/deploy-vps.md).  
Push FCM: [docs/diagnostico-push.md](docs/diagnostico-push.md) y
`scripts/deploy_push_fcm_vps.sh`. Health debe reportar `"fcm_disponible": true`.

Flujo:

1. El colegio registra llegada/salida/incidencia en SIE JP.
2. SIE hace `POST` de ingesta al canal (ya no WhatsApp/WPP).
3. El backend crea el mensaje y notifica por push (FCM) si el dispositivo está registrado.
4. El apoderado abre Asis Messenger y ve la bandeja vía HTTPS al VPS.
