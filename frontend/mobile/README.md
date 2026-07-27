# Asiscole Messenger — app del apoderado

Canal móvil que reemplaza a WhatsApp para avisar al apoderado de entradas, salidas,
incidencias y avisos. El apoderado es **solo receptor**.

## Qué incluye esta entrega

- Autenticación completa (login, sesión única, transferencia, suspensión)
- Bandeja de mensajes con caché offline (SQLite)
- Asistencias e incidencias (requieren conexión)
- Notas visibles y desactivadas por feature flag (`Próximamente`)
- Perfil multi-hijo y eliminación de cuenta
- Push: deep-link a mensajes/incidencias y aprobación de transferencia
- UI de marca (paleta morado/celeste, logo, barra flotante, fondos decorativos)

## Diseño UI (marca Asiscole)

| Token | Color |
| --- | --- |
| Morado principal | `#5B21E6` |
| Morado secundario | `#7C3AED` |
| Morado claro | `#A855F7` |
| Celeste | `#22C7F2` |
| Texto | `#0F172A` |
| Fondo | `#F8FAFC` |

- Tema central: `lib/core/theme/app_theme.dart`
- Logo: `assets/brand/logo_asiscole.png` (también icono de launcher)
- Shell: barra inferior flotante tipo píldora (5 pestañas)
- Fondos: `FondoAsiscole` con composición distinta por pantalla (`login`, `mensajes`, `asistencias`, `incidencias`, `notas`, `perfil`)
- Mensajes: búsqueda local, chips Todos / No leídos, detalle solo lectura
- Asistencias: grid mensual + detalle del día
- Incidencias: cards cronológicas + sheet de detalle
- Login / Perfil: header de marca y tipografía alineada a la paleta

No se tocan contratos OpenAPI ni Cubits de negocio en el rediseño visual.

## Rendimiento (buenas prácticas aplicadas)

- Arranque: Firebase/push diferidos al primer frame; TZ con dataset `latest` (no `latest_all`)
- Logo con `cacheWidth` / `cacheHeight`
- Tokens de sesión en caché de memoria (menos Keystore por request)
- Mensajes: marcar leído optimista; búsqueda con debounce; refrescos silenciosos
- Caché corta de `/perfil` y dedupe del push-token

## Requisitos

- Flutter 3.41 o superior
- Backend del canal:
  - **Producción (APK release):** ya apunta a
    `https://jeanpiaget.asiscole.com/canal-api/v0.1`
  - **Desarrollo:** Django local (`docker compose` / `runserver`) o
    `--dart-define=API_BASE_URL=...`
- Para **push FCM** (opcional al compilar): coloca por canal privado
  - `android/app/google-services.json`
  - `lib/firebase_options.dart` (o genera con `flutterfire configure`)
  Hay plantillas `*.example` en esas carpetas. Sin el JSON, la app igual compila
  (el plugin de Google Services solo se aplica si el archivo existe).

## Cómo funciona con el VPS

```
SIE Jean Piaget (nube)
  → POST /canal-api/v0.1/ingesta/eventos
  → Django en el VPS crea el aviso en la BD central del canal
  → push FCM (si hay token) + bandeja en la app

App Asiscole Messenger (APK)
  → HTTPS https://jeanpiaget.asiscole.com/canal-api/v0.1/...
  → login, mensajes, asistencias, incidencias, perfil
```

Health del backend: https://jeanpiaget.asiscole.com/canal-api/health  
Docs: https://jeanpiaget.asiscole.com/canal-api/v0.1/docs/

## Cómo correr

### Producción / VPS (por defecto)

La app apunta a `https://jeanpiaget.asiscole.com/canal-api/v0.1` en debug y release.

```powershell
cd frontend/mobile
# Copia Firebase de secrets/ (una vez, no va a Git):
#   secrets\secrets\firebase_options.dart → lib\firebase_options.dart
#   secrets\secrets\google-services.json → android\app\google-services.json
flutter pub get
.\run_dispositivo.ps1
```

### Desarrollo local (Django en tu PC)

```powershell
cd backend
..\.\.venv\Scripts\Activate.ps1
python manage.py runserver 0.0.0.0:8000
```

```powershell
cd frontend/mobile
.\run_dispositivo.ps1 -Local -Ip 192.168.100.6
```

| Entorno | URL |
| --- | --- |
| **VPS (default)** | `https://jeanpiaget.asiscole.com/canal-api/v0.1` |
| Celular + Django local | `.\run_dispositivo.ps1 -Local` |
| Emulador + Django local | `--dart-define=API_BASE_URL=http://10.0.2.2:8000/v0.1` |

## Generar APK (Asiscole Messenger)

```powershell
cd frontend/mobile
flutter pub get
flutter build apk --release
```

El artefacto queda en:

`build/app/outputs/flutter-apk/app-release.apk`

Se puede renombrar a `Asiscole_Messenger.apk` para distribución. El nombre visible
en el dispositivo (launcher) es **Asiscole Messenger** (`AndroidManifest`).

## Navegación (RF-K)

Mensajes · Asistencias · Incidencias · Notas · Perfil

## Consumo de datos (pruebas)

En **debug**, Dio registra un acumulado aproximado de bytes (`api.bytes` en el
log): solo tamaños / `Content-Length`, sin cuerpos ni PII.

Recomendación de prueba:

1. Arranque en frío con Wi‑Fi → anotar `enviados` / `recibidos` tras abrir Mensajes.
2. Repetir en datos móviles tras un sync previo (debe bajar gracias a `since` +
   caché de `/perfil`).
3. Evitar pull-to-refresh continuo: la sync incremental no re-baja toda la bandeja
   si ya hay mensajes en SQLite (margen de 6 h sobre la última marca).

Push lento (horas): ver [docs/diagnostico-push.md](../../docs/diagnostico-push.md).
