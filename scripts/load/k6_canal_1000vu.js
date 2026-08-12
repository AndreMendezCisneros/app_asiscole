/**
 * Carga agresiva para VPS Opción B (~8 CPU / 32 GB, Gunicorn 8×4).
 *
 * Uso (staging / ventana acordada — NO en horario escolar a ciegas):
 *   k6 run -e BASE_URL=https://host/canal-api/v0.1 \
 *          -e DATA_TOKEN=eyJ... \
 *          scripts/load/k6_canal_1000vu.js
 *
 * Un solo data_token de cuenta de prueba (no 1000 logins: sesión única).
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '1m', target: 100 },
    { duration: '2m', target: 300 },
    { duration: '2m', target: 500 },
    { duration: '3m', target: 1000 },
    { duration: '2m', target: 1000 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<800'],
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
  errorRate.add(!check(perfil, { 'perfil 200': (r) => r.status === 200 }));

  const mensajes = http.get(`${BASE}/mensajes?limit=50`, { headers });
  errorRate.add(!check(mensajes, { 'mensajes 200': (r) => r.status === 200 }));

  sleep(0.5 + Math.random());
}
