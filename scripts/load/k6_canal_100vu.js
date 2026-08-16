/**
 * Línea base del host actual (Hetzner compartido ~4 vCPU / 8 GB, Gunicorn 3×2).
 *
 * NO usar el script de 1000 VU contra este host: mide el techo de 6 workers y
 * puede degradar el SIE que vive en la misma máquina.
 *
 * Uso (staging o prod fuera de horario escolar, con OK explícito):
 *   k6 run -e BASE_URL=https://jeanpiaget.asiscole.com/canal-api/v0.1 \
 *          -e DATA_TOKEN=eyJ... \
 *          scripts/load/k6_canal_100vu.js
 *
 * Un data_token de cuenta de prueba (no login masivo: sesión única + rate-limit).
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '30s', target: 15 },
    { duration: '1m', target: 30 },
    { duration: '1m', target: 40 },
    { duration: '1m', target: 40 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<1500'],
    errors: ['rate<0.02'],
  },
};

const BASE = (__ENV.BASE_URL || 'http://127.0.0.1:8000/v0.1').replace(/\/$/, '');
const TOKEN = __ENV.DATA_TOKEN || '';

export default function () {
  if (!TOKEN) {
    throw new Error('Define DATA_TOKEN (data_token de una cuenta de prueba).');
  }
  const headers = {
    Authorization: `Bearer ${TOKEN}`,
    Accept: 'application/json',
  };

  const perfil = http.get(`${BASE}/perfil`, { headers });
  const okPerfil = check(perfil, { 'perfil 200': (r) => r.status === 200 });
  errorRate.add(!okPerfil);

  const mensajes = http.get(`${BASE}/mensajes?limit=50`, { headers });
  const okMsg = check(mensajes, { 'mensajes 200': (r) => r.status === 200 });
  errorRate.add(!okMsg);

  sleep(1);
}
