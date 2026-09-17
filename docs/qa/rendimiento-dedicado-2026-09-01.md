# Rendimiento — VPS dedicado (2026-09-01)

Host: `asiscole-ded1` (`138.201.203.50`), 8 CPU / 62 GB. Canal en
`/opt/asiscole-canal` con **Gunicorn 8×4**, Celery 6, Redis 2 GB. El SIE sigue
en la misma máquina. k6 contra `http://127.0.0.1:8000/v0.1` (sin Cloudflare).

Por Cloudflare, 1 VU ya daba p95 ~1,6 s (RTT); no sirve para medir Gunicorn.

## Resultados

| Prueba | VU / iters | p95 | Fallos HTTP | CPU backend (pico) | RAM backend | Umbral |
| --- | --- | --- | --- | --- | --- | --- |
| Lectura 40 VU, 4 min | 40 | **747 ms** | 0 % (6984 OK) | ~41 % | ~549 MiB | p95 &lt; 1,5 s **pasa** |
| Lectura 200 VU, 3 min | 200 | **3,68 s** | 0 % | (cola) | ~590 MiB | p95 &lt; 1,5 s **falla** |
| Lectura 800 VU, 8 min | 800 | **14,5 s** | 0 % | **222 %** (~2,2 núcleos) | ~591 MiB | p95 &lt; 800 ms **falla** |
| Ingesta 800 POST (sin destinatario) | 32 VU / 800 | **330 ms** | 0 % (800×202, `creados: 0`) | baja | estable | p95 &lt; 2 s **pasa** |

Durante el pico de 800 VU, `GET /health` local **agotó 8 s** (workers ocupados).
Al terminar, health volvió a `ok` + `fcm_disponible: true`. Redis ~4 MiB / 2,5 GiB.

800 VU en bucle (2 GET cada ~1 s) es **más duro** que 800 padres abriendo la app
una vez. 200 VU en bucle ya pone p95 en 3,7 s.

## Veredicto

- **800 apoderados al día:** sí. 40 lecturas concurrentes (más que un recreo
  normal) responden bajo 800 ms en el origen, 0 errores, RAM irrelevante.
- **Pico 14:45 de 800 avisos sin fan-out FCM:** sí. 800 POST de ingesta en 8,6 s,
  p95 330 ms, todos `creados: 0` (estudiante sintético, **sin push**).
- **800 padres martillando la API a la vez:** no con p95 &lt; 800 ms. Cero
  errores, pero cola: 5–15 s. El health del canal se queda mudo unos segundos.
  Un recreo real (3–5 peticiones y se quedan leyendo) se parece más a **40–80 VU**,
  no a 800 bucles.

## Lote de 20 push reales

No se envió. Habría requerido un `id_estudiante` de una cuenta de prueba tuya;
usar una sesión aleatoria habría disparado FCM a un padre real. El k6 de ingesta
**no** mide FCM síncrono (ese camino solo corre si `creados &gt; 0`).

## Qué puede fallar (observado vs. teórico)

| Riesgo | ¿Se vio? |
| --- | --- |
| Cola HTTP con muchos GET concurrentes | Sí a 200 y 800 VU (p95 3,7 s / 14,5 s) |
| Health/SIE lentos en el pico | Health local timeout 8 s a ~500–800 VU |
| Ingesta 800 sin destinatario | No: p95 330 ms |
| FCM en el mismo hilo HTTP (800 avisos *con* padre) | No medido; sigue siendo el riesgo del 14:45 real |
| Redis 256 MB | Mitigado: ahora 2 GB, usó 4 MiB |
| Cloudflare / p95 de red | 1 VU público ~1,6 s; no es Gunicorn |
| Login masivo día 1 | No probado (sesión única + rate-limit) |
| 20 push a tu teléfono | Omitido a propósito |

Mitigación futura del 14:45 *con* destinatarios: mandar `enviar_push_mensaje` a
Celery (`.delay`) para no ocupar las 32 ranuras HTTP esperando a Google.

Scripts: [`k6_canal_100vu.js`](../../scripts/load/k6_canal_100vu.js),
[`k6_canal_200vu.js`](../../scripts/load/k6_canal_200vu.js),
[`k6_canal_800vu.js`](../../scripts/load/k6_canal_800vu.js),
[`k6_ingesta_800.js`](../../scripts/load/k6_ingesta_800.js).
