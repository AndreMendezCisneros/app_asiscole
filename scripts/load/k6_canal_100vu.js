/**
 * Smoke de carga: 100 usuarios virtuales contra el canal.
 *
 * Uso (staging, NUNCA en horario escolar sin acuerdo):
 *   k6 run -e BASE_URL=https://host/canal-api/v0.1 \
 *          -e DATA_TOKEN=eyJ... \
 *          scripts/load/k6_canal_100vu.js
 *
 * Los VUs reutilizan un data_token de una cuenta de prueba (no hacen login
 * masivo: sesión única + rate-limit).
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '1m', target: 50 },
    { duration: '1m', target: 100 },
    { duration: '1m', target: 100 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<800'],
    errors: ['rate<0.01'],
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
