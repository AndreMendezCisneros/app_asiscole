#!/usr/bin/env bash
# Cutover de producción en el VPS del canal (/opt/asiscole-canal).
#
# Ejecutar EN EL SERVIDOR:
#   cd /opt/asiscole-canal
#   git pull origin master
#   bash scripts/ops_prod_cutover.sh
#
# 1) Valida .env (REDIS_PASSWORD, DEBUG=False, secret ≥32)
# 2) docker compose build + up (Opción B)
# 3) migrate
# 4) aplica 007_central_rls_lockdown.sql en BD central
# 5) health

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
COMPOSE=(docker compose -f docker-compose.prod.yml)

echo "==> [1/5] Validando .env"

if [[ ! -f .env ]]; then
  if [[ -f .env.production.example ]]; then
    cp .env.production.example .env
    chmod 600 .env
    echo "Creado .env desde .env.production.example — completa secretos y reejecuta."
    exit 1
  fi
  echo "Falta .env"
  exit 1
fi

require_env() {
  local key="$1"
  if ! grep -qE "^${key}=.+" .env; then
    echo "Falta o vacío en .env: ${key}"
    exit 1
  fi
}

require_env DJANGO_SECRET_KEY
require_env REDIS_PASSWORD
require_env REDIS_URL
require_env CENTRAL_DB_HOST

if grep -qE '^DJANGO_DEBUG=(True|true|1)' .env; then
  echo "DJANGO_DEBUG debe ser False en producción."
  exit 1
fi

SECRET="$(grep -E '^DJANGO_SECRET_KEY=' .env | head -1 | cut -d= -f2- | tr -d '\r')"
if [[ ${#SECRET} -lt 32 ]] || [[ "$SECRET" == "cambiar-en-produccion" ]] || [[ "$SECRET" == "REEMPLAZAR_CON_SECRET_ALEATORIO_LARGO" ]]; then
  echo "DJANGO_SECRET_KEY insegura o placeholder (mín. 32 chars reales)."
  exit 1
fi

if ! grep -qE '^REDIS_URL=redis://:' .env; then
  echo "REDIS_URL debe ser redis://:PASSWORD@redis:6379/0"
  exit 1
fi

if [[ ! -f secrets/fcm-adminsdk.json ]]; then
  echo "AVISO: falta secrets/fcm-adminsdk.json (push FCM no funcionará)."
fi

echo "==> [2/5] Build + up"
"${COMPOSE[@]}" build backend worker beat
"${COMPOSE[@]}" up -d

echo "==> [3/5] Migraciones Django"
"${COMPOSE[@]}" exec -T backend python manage.py migrate --noinput

echo "==> [4/5] RLS lockdown central (007)"
SQL_FILE="db/migrations/007_central_rls_lockdown.sql"
if [[ ! -f "$SQL_FILE" ]]; then
  echo "No está $SQL_FILE en el host — aplícalo en Supabase SQL Editor."
else
  "${COMPOSE[@]}" cp "$SQL_FILE" backend:/tmp/007_central_rls_lockdown.sql
  "${COMPOSE[@]}" exec -T backend python - <<'PY'
from pathlib import Path
import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from django.db import connection

sql = Path("/tmp/007_central_rls_lockdown.sql").read_text(encoding="utf-8")
# psycopg3: execute acepta scripts multi-statement con autocommit.
raw = connection.connection
if raw is None:
    connection.ensure_connection()
    raw = connection.connection
raw.autocommit = True
with raw.cursor() as cur:
    cur.execute(sql)
print("RLS 007 aplicado OK")
PY
fi

echo "==> [5/5] Health"
sleep 2
curl -sS http://127.0.0.1:8000/health || true
echo
echo "Cutover listo. Comprueba https://TU_DOMINIO/canal-api/health"
echo "Distribuye el APK nuevo (flujo de traspaso requiere token_consulta)."
