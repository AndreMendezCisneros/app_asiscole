# Asiscole — Canal de notificación al apoderado

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

- [docs/openapi.yaml](docs/openapi.yaml) — contrato de API `/v0.1/`. Es contract-first:
  ningún cliente consume un endpoint que no esté antes aquí.
- [db/legacy/bootstrap_colegio.sql](db/legacy/bootstrap_colegio.sql) — esquema del colegio.
- [db/migrations](db/migrations) — SQL del canal, aditivo.
