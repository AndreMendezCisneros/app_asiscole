/**
 * Escalón medio: ~200 apoderados abriendo la app a la vez.
 *
 *   k6 run -e BASE_URL=http://127.0.0.1:8000/v0.1 -e DATA_TOKEN=... \
 *          scripts/load/k6_canal_200vu.js
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '30s', target: 100 },
    { duration: '1m', target: 200 },
    { duration: '1m', target: 200 },
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
  errorRate.add(!check(perfil, { 'perfil 200': (r) => r.status === 200 }));
  const mensajes = http.get(`${BASE}/mensajes?limit=50`, { headers });
  errorRate.add(!check(mensajes, { 'mensajes 200': (r) => r.status === 200 }));
  sleep(0.5 + Math.random());
}
