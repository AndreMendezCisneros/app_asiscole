/**
 * Pico de ingesta (~800 POST, escenario 14:45).
 *
 * Usa un id_estudiante inexistente: creados=0, sin push a padres reales.
 * Mide HTTP + directorio + Gunicorn, no FCM síncrono.
 *
 *   k6 run -e BASE_URL=https://jeanpiaget.asiscole.com/canal-api/v0.1 `
 *          -e INGEST_KEY=... `
 *          -e TENANT_ID=jean_piaget `
 *          scripts/load/k6_ingesta_800.js
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

const errorRate = new Rate('errors');
const aceptados = new Counter('ingesta_202');
const creadosCero = new Counter('ingesta_creados_0');

export const options = {
  scenarios: {
    burst: {
      executor: 'shared-iterations',
      vus: 32,
      iterations: 800,
      maxDuration: '5m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
    errors: ['rate<0.05'],
  },
};

const BASE = (__ENV.BASE_URL || 'http://127.0.0.1:8000/v0.1').replace(/\/$/, '');
const KEY = __ENV.INGEST_KEY || '';
const TENANT = __ENV.TENANT_ID || 'jean_piaget';

export default function () {
  if (!KEY) {
    throw new Error('Define INGEST_KEY (INGEST_API_KEY del .env, no commitear).');
  }
  const idRegistro = 900000000 + (__VU * 100000) + __ITER;
  const cuerpo = JSON.stringify({
    tenant_id: TENANT,
    tipo: 'entrada',
    id_estudiante: 2147483000,
    id_registro: idRegistro,
    payload: {
      id_estudiante: 2147483000,
      nombre_completo: 'carga-sintetica',
      hora: '14:45',
    },
  });
  const res = http.post(`${BASE}/ingesta/eventos`, cuerpo, {
    headers: {
      'Content-Type': 'application/json',
      'X-Asiscole-Ingest-Key': KEY,
      Accept: 'application/json',
    },
  });
  const ok = check(res, { 'ingesta 202': (r) => r.status === 202 });
  errorRate.add(!ok);
  if (res.status === 202) {
    aceptados.add(1);
    try {
      const j = res.json();
      if (j && j.creados === 0) creadosCero.add(1);
    } catch (e) {
      /* cuerpo no JSON */
    }
  }
  sleep(0.05);
}
