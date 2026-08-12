# Diagnóstico push (evento → FCM)

Cuando un aviso tarda **minutos u horas** en llegar al teléfono, el retraso casi
nunca está en la app: el canal encola en `asis_outbox` (colegio) → poller →
mensaje central → Celery/FCM.

Estado del VPS JP (FCM ya activo tras cutover): [`estado-produccion.md`](estado-produccion.md).

## Cadena esperada (métrica evento→push)

| Paso | Qué mirar | Latencia normal |
| --- | --- | --- |
| 1. SIE escribe en BD colegio | Trigger `asis_fn_encolar_evento` | inmediato |
| 2. Poller lee `asis_outbox` | Celery beat `poller-outbox` (cada ~10 s) o `POLL_OUTBOX_INLINE` | ≤ 15 s |
| 3. Genera `asis_mensaje` + outbox push | logs `outbox_evento_error` / worker | segundos |
| 4. FCM entrega | credenciales Firebase + token del dispositivo | segundos–minutos |

## Sonda rápida

```text
GET https://jeanpiaget.asiscole.com/canal-api/health
→ { "status": "ok", "fcm_disponible": true|false }
```

Si `fcm_disponible` es `false`, el worker/backend está en **modo simulado** y
**no** llegará nada a la bandeja del teléfono aunque el token esté registrado.

## Activar FCM en el VPS (docker-compose.prod.yml)

1. Copia el JSON de cuenta de servicio Firebase Admin (mismo proyecto que
   `google-services.json` de la app) a:
   `secrets/fcm-adminsdk.json` en el host del VPS (carpeta montada en el compose).
2. En el `.env` de producción:
   ```bash
   FCM_CREDENTIALS_PATH=/secrets/fcm-adminsdk.json
   ```
3. Rebuild y reinicio:
   ```bash
   docker compose -f docker-compose.prod.yml up -d --build backend worker beat
   ```
4. Verifica `GET /canal-api/health` → `fcm_disponible: true`.
5. En logs del worker **no** debe aparecer `push_simulado`.

Canal Android de la app: `asiscole_avisos_v2` (sonido). Debe coincidir con
`channel_id` en `apps/mensajeria/push/fcm.py`.

## Checklist VPS (sin PII)

1. **Worker y beat vivos**
   - `celery -A config worker` y `celery -A config beat` corriendo
   - Si `POLL_OUTBOX_INLINE=True` solo aplica a `runserver` local; en producción debe ser `False`
2. **Cola / Redis**
   - Broker alcanzable; no hay backlog enorme en la cola de push
3. **Credenciales FCM**
   - `FCM_CREDENTIALS_PATH` apunta a un fichero legible **dentro** del contenedor
   - Fallos FCM: loguear solo códigos / request_id, **nunca** teléfono ni texto del mensaje
4. **Circuito colegio**
   - Si el poller salta el tenant (`poller_salta_circuito_abierto`), la BD del colegio está caída o en circuit breaker
5. **Token del dispositivo**
   - Log app: `push activo` + `PUT /perfil/push-token → 204`
6. **Xiaomi / MIUI**
   - Notificaciones de la app ON; evitar “batería restringida” / sin autostart si bloquea FCM

## Comando de una pasada (ops)

```bash
python manage.py poll_outbox
```

Útil si beat estaba caído: vacía pendientes de todos los colegios una vez.

## Verificar después del deploy

```powershell
# Health debe incluir fcm_disponible true
Invoke-RestMethod https://jeanpiaget.asiscole.com/canal-api/health
```

App: rebuild, login, generar entrada en SIE con la app en segundo plano → shade + sonido.
Hora en lista: **1:xx p. m.** (no 6:xx p. m.).
