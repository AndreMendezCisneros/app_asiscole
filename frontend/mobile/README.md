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
- Backend Asiscole en local (`docker compose` + `runserver`)
- El archivo `android/app/google-services.json` viene en el repo (Firebase cliente).
  Sin él, Gradle falla en `processDebugGoogleServices`.

## Cómo correr

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
| Emulador Android | `http://10.0.2.2:8000/v0.1` (default) |
| **Celular físico (misma Wi‑Fi)** | `http://IP_DE_TU_PC:8000/v0.1` — obligatorio con `--dart-define` |
| iOS simulador / escritorio | `http://localhost:8000/v0.1` |

Ejemplo con la IP de tu PC en la LAN:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.18.206:8000/v0.1
```

Si usas `10.0.2.2` en un **celular real**, el login falla con “El servidor tardó demasiado” porque esa dirección solo existe en el emulador.
## Push

Sin `google-services.json` / `GoogleService-Info.plist` el servicio queda inactivo y la
app funciona igual. Al añadir Firebase se activa solo.

## Navegación (RF-K)

Mensajes · Asistencias · Incidencias · Notas · Perfil
