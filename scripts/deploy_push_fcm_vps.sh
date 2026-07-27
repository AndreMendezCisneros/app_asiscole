# Despliegue push FCM en el VPS (Jean Piaget)
# Ejecutar en el host donde vive docker-compose.prod.yml (como root o con docker).
#
# Prerrequisitos en el host:
#   1. secrets/fcm-adminsdk.json  (cuenta de servicio Firebase Admin)
#   2. En .env: FCM_CREDENTIALS_PATH=/secrets/fcm-adminsdk.json
#   3. Código actualizado (git pull) con firebase-admin en requirements.txt
#      y channel_id asiscole_avisos_v2 + emitido_en con Z.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f secrets/fcm-adminsdk.json ]]; then
  echo "Falta secrets/fcm-adminsdk.json (JSON Admin del mismo proyecto Firebase que la app)."
  exit 1
fi

if ! grep -q 'FCM_CREDENTIALS_PATH=/secrets/fcm-adminsdk.json' .env 2>/dev/null; then
  echo "Asegura en .env: FCM_CREDENTIALS_PATH=/secrets/fcm-adminsdk.json"
  exit 1
fi

docker compose -f docker-compose.prod.yml build backend worker beat
docker compose -f docker-compose.prod.yml up -d backend worker beat

echo "Espera health..."
sleep 3
curl -sS http://127.0.0.1:8000/health || true
echo
echo "Listo. En el worker no debe aparecer push_simulado."
