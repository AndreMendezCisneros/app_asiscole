# Fase 4 — Estrés y rendimiento

Fecha: 2026-08-13.

**No se ejecutó carga.** Dos razones: `k6` no está instalado en esta máquina, y el
único entorno con datos reales es producción, que comparte VPS con el SIE del
colegio. La prueba queda preparada y esperando tu OK con una ventana horaria.

---

## Capacidad real frente a la que asumen los scripts

Aquí está el hallazgo más importante de la fase, y es de método:

| | Opción B (para lo que se escribieron los scripts) | Producción hoy |
| --- | --- | --- |
| Host | VPS dedicado ~8 CPU / 32 GB | Hetzner **compartido con el SIE**, ~4 vCPU / 8 GB |
| Gunicorn | 8 workers × 4 threads = **32** peticiones en paralelo | 3 × 2 = **6** |
| Celery | 6 | 2 |
| Redis | 2 GB | 256 MB |

Los dos scripts de carga fijan el mismo umbral (`http_req_duration p(95) < 800 ms`,
fallos < 1-2 %) y el de 1000 VU lo dice explícitamente en su cabecera: está pensado
para Gunicorn 8×4. Con seis ranuras de concurrencia, 100 VU haciendo dos peticiones
por iteración generan una cola de espera que hará fallar el umbral por diseño, no
por regresión.

**Recomendación.** Antes de correr nada, decidir qué se quiere medir:

- Si se quiere **validar el host actual**: bajar el objetivo a 30-50 VU y subir el
  umbral a `p(95) < 1500 ms`, y documentar ese número como la línea base del
  hardware compartido. Un resultado verde ahí sí es información útil.
- Si se quiere **validar Opción B**: no tiene sentido medirlo en este host. Se
  ejecuta cuando exista el VPS dedicado.

Correr el script de 1000 VU tal cual contra el VPS compartido no mide el canal:
mide el límite de seis workers, y con el riesgo añadido de degradar el SIE del
colegio, que vive en la misma máquina.

## Qué cubren los scripts y qué no

`k6_canal_100vu.js` y `k6_canal_1000vu.js` piden `GET /perfil` y
`GET /mensajes?limit=50` reutilizando un `data_token` de cuenta de prueba. La
decisión de no hacer login masivo es correcta y deliberada: sesión única más
rate-limit harían que 100 logins concurrentes midieran el bloqueo, no el servidor.

Lo que ningún script cubre hoy:

1. **El pico real del canal, que es la ingesta.** Entre 7:00 y 8:00 cada estudiante
   marca entrada. Con `LOTE_OUTBOX = 100` y el poller cada 10 s, el techo teórico es
   de 600 eventos por minuto y colegio; un colegio de 800 estudiantes concentrados
   en 40 minutos son unos 20 eventos por minuto, holgadísimo. Pero cada evento
   dispara render de plantilla, escritura en la central y una tarea de push, y eso
   es Celery con concurrencia 2. Vale la pena medir el retraso de extremo a extremo
   (marca en el torniquete → notificación en el teléfono) con un lote sintético en
   un tenant de prueba, más que medir peticiones HTTP.
2. **El pico de login del primer día.** Es el escenario más caro: resolver el
   directorio puede tocar la base del colegio, y es el único endpoint que no se
   beneficia de la caché si el apoderado es nuevo. Un rollout de Play al 5-10 %
   mitiga esto mejor que cualquier ajuste de servidor.
3. **Un colegio caído.** El circuit breaker y el timeout de 2 segundos están
   probados a nivel unitario, pero no bajo carga simultánea.

## Lado app

Revisión estática, sin instrumentación en dispositivo.

### Bien resuelto

- **Un solo refresco de token** aunque caduque con varias peticiones en vuelo
  (`AuthInterceptor._renovarUnaSolaVez`), con prueba que lo verifica.
- **Suscripciones cerradas.** `AuthCubit.close` cancela eventos, red, sondeo y
  debounce; `MensajesPage.dispose` cancela avisos push, debounce y observer del
  ciclo de vida; `SessionStorage` cachea en memoria para no golpear el Keystore en
  cada petición.
- **Lista eficiente.** `ListView.separated` con `cacheExtent: 720`, `ValueKey` por
  fila, `buildWhen` acotado en el `BlocBuilder` y `DateFormat` reutilizado en
  estáticos (construirlo por fila es caro en scroll).
- **Búsqueda con debounce** de 220 ms.
- **Marcado de leído optimista** con cola local (`leidos_pendientes`) que se reenvía
  en el siguiente sync.

### T-01 · Los timeouts son demasiado largos para un móvil

**Severidad: media.**

```42:43:frontend/mobile/lib/core/config/env.dart
  static const Duration timeoutConexion = Duration(seconds: 20);
  static const Duration timeoutRespuesta = Duration(seconds: 30);
```

Con cobertura mala, el apoderado mira un spinner hasta 20 segundos antes de recibir
«Sin conexión a internet». En una app cuyo valor es enterarse rápido de si su hijo
llegó, eso se percibe como que la app no funciona. Peor en el arranque: `iniciar()`
hace `refrescarDatosAlArranque()` antes de mostrar la bandeja, así que el usuario
puede quedarse hasta 20 segundos en la pantalla de carga antes de caer a modo
offline y ver la caché que ya tenía en el teléfono.

**Recomendación.** Bajar la conexión a 8-10 segundos y, sobre todo, mostrar la
caché primero y refrescar por detrás en el arranque, en lugar de esperar la red
para decidir.

### T-02 · Cada vuelta a la app dispara una sincronización completa

**Severidad: baja.**

```79:84:frontend/mobile/lib/features/mensajes/presentation/mensajes_page.dart
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<MensajesCubit>().cargar(silencioso: true);
    }
  }
```

Alternar entre la app y WhatsApp diez veces lanza diez sincronizaciones. Cada una
es al menos una petición (`since` acotado, así que el payload es pequeño), pero es
consumo de datos y batería evitable.

**Recomendación.** No refrescar si el último sync fue hace menos de 30-60 segundos.

### T-03 · El sondeo del traspaso no tiene fin

**Severidad: baja.**

`AuthCubit.iniciarSondeoTransferencia` crea un `Timer.periodic` de 5 segundos
(`Env.intervaloSondeoTransferencia`) que solo se detiene si la solicitud se
resuelve, expira o el usuario sale de la pantalla. La solicitud vive 5 minutos
(`TRANSFER_REQUEST_TTL_MINUTES`), así que en el peor caso son 60 peticiones. No es
grave, pero un tope explícito de intentos evitaría que un estado inesperado deje el
temporizador vivo.

---

## Plan de ejecución propuesto (a la espera de tu OK)

1. **Ventana:** día no escolar o después de las 19:00 de Lima, con el SIE con poca
   actividad.
2. **Previo:** instalar `k6`, crear una cuenta de apoderado de prueba y obtener su
   `data_token`, y dejar abierta la vista de `docker stats` en el VPS.
3. **Escalón 1 (línea base del host actual):** 30 VU, 3 minutos, umbral
   `p(95) < 1500 ms`. Si esto no pasa, no hay que subir más: hay un problema que
   arreglar antes.
4. **Escalón 2:** 50 VU y luego 100 VU, anotando en cada uno CPU, RAM y si Redis
   toca su límite de 256 MB.
5. **Criterio de parada:** cortar de inmediato si el SIE se degrada o si los fallos
   pasan del 5 %.
6. **Ingesta:** por separado, un lote de 200 eventos sintéticos en un tenant de
   prueba, midiendo el tiempo hasta que el mensaje aparece en la bandeja y hasta que
   llega el push.
7. **Entregable:** una tabla con VU, `p(95)`, tasa de fallos y consumo del host, que
   pase a ser la línea base contra la que comparar el siguiente release.

**Sin ese OK, esta fase queda en verde documental: no hay evidencia de que el canal
aguante el pico, solo de que no hay nada evidentemente mal diseñado.** Con dos
colegios y un rollout escalonado, ese riesgo es asumible; con diez colegios, no.
