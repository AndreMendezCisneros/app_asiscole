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

### Producción (contra el VPS)

```powershell
cd frontend/mobile
flutter pub get
flutter build apk --release
# o, en debug pero ya contra el VPS:
flutter run --release
# o forzar la URL en debug:
flutter run --dart-define=API_BASE_URL=https://jeanpiaget.asiscole.com/canal-api/v0.1
```

### Desarrollo local (Django en tu PC)

Backend (escucha en todas las interfaces, necesario para celular físico):

```powershell
cd backend
..\.\.venv\Scripts\Activate.ps1
python manage.py runserver 0.0.0.0:8000
```

App:

```powershell
cd frontend/mobile
flutter pub get
flutter run
```

| Entorno | URL |
| --- | --- |
| **APK release / producción** | `https://jeanpiaget.asiscole.com/canal-api/v0.1` |
| Emulador Android (local) | `http://10.0.2.2:8000/v0.1` |
| **Celular físico (misma Wi‑Fi, local)** | `http://IP_DE_TU_PC:8000/v0.1` — con `--dart-define` |
| iOS simulador / escritorio (local) | `http://localhost:8000/v0.1` |

Ejemplo con la IP de tu PC en la LAN:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.100.6:8000/v0.1
```

Si usas `10.0.2.2` en un **celular real**, el login falla con “El servidor tardó demasiado” porque esa dirección solo existe en el emulador.
## Push

Sin `google-services.json` / `GoogleService-Info.plist` el servicio queda inactivo y la
app funciona igual. Al añadir Firebase se activa solo.

## Navegación (RF-K)

Mensajes · Asistencias · Incidencias · Notas · Perfil
