# Lanzamiento Play — Asis Messenger

Fecha: 2026-08-16. Nombre visible: **Asis Messenger**. El id interno no cambia:
`pe.asiscole.asiscole_app` (si lo cambias, Play lo trata como otra app).

Haz los pasos **en este orden**. No saltes el 0 ni el 2: el resto depende de ellos.

---

## 0. Correo de soporte (hoy no funciona)

La app y `https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta` publican
`soporte@asiscole.com`. En DNS de `asiscole.com` **no hay MX**: ese correo no
llega a nadie. Play lo usa como contacto y lo rechaza si rebota.

Elige una:

**A (recomendada).** Crear el buzón en el dominio (Google Workspace / Zoho / el
proveedor del colegio) y añadir MX + SPF.

**B.** Usar un buzón que ya exista (por ejemplo el del colegio) y cambiar las
dos constantes:

- `frontend/mobile/lib/core/config/env.dart` → `correoSoporte`
- `backend/apps/common/paginas.py` → `CORREO_SOPORTE`

Prueba: envíate un mail a esa dirección desde Gmail y confirma que entra.

---

## 1. Sacar secretos de Git y no volver a meterlos

En PowerShell, desde la raíz del repo:

```powershell
# Firebase cliente está en .gitignore PERO sigue trackeado. Si no haces esto,
# el próximo commit lo sube a GitHub.
git rm --cached frontend/mobile/lib/firebase_options.dart

# key.properties ya está en .gitignore (recién). No lo crees antes de este paso.
```

Comprueba que `secrets/` no aparece en `git status`. Los archivos reales viven en:

- `secrets/secrets/firebase_options.dart`
- `secrets/secrets/google-services.json`
- `secrets/fcm-adminsdk.json`

Eso ya está. No los copies al commit.

---

## 2. Keystore de release + copia de seguridad

Sin esto, `build_apk.ps1` y `build_aab.ps1` **fallan**. La clave de debug es
pública: no la uses para el colegio ni para Play.

```powershell
cd frontend/mobile
New-Item -ItemType Directory -Force -Path android\keystore | Out-Null

keytool -genkeypair -v `
  -keystore android\keystore\asiscole-release.jks `
  -keyalg RSA -keysize 4096 -validity 10000 `
  -alias asiscole

Copy-Item android\key.properties.example android\key.properties
notepad android\key.properties
```

En `key.properties` pon las mismas contraseñas que usaste en `keytool`.
`storeFile` debe quedar así (ruta relativa a `android/`):

```
storeFile=keystore/asiscole-release.jks
```

**Copia de seguridad (obligatoria):** USB cifrado, gestor de secretos o nube
privada. Guarda `.jks` + `key.properties` + las contraseñas. Si se pierde la
clave de **carga**, Play obliga a publicar una app nueva. En el primer AAB
deja que Play gestione la clave de firma (Play App Signing).

---

## 3. Commit y push (selectivo)

No uses `git add -A` ni `commit -a`. Queda mucho `_tmp_*`, `.gradle` y
`firebase_options.dart`.

Incluye, a grandes rasgos:

- backend (notas, citas, versión, eliminar-cuenta, push title)
- app Flutter (Asis Messenger, Notas, Crashlytics, versión)
- `docs/`, `docs/openapi.yaml`, migraciones `administracion.0004`
- `.gitignore` con `key.properties`

No incluyas: `secrets/`, `*.jks`, `key.properties`, `google-services.json`,
`_tmp_*`, `build/`, APK/AAB.

Cuando esté listo, pide el commit en el chat o hazlo tú. Push a `origin/master`
solo cuando hayas revisado `git status` y `git diff --cached`.

El VPS **no** se actualiza con `git pull` (no es un clone). El código de
producción se copia con tar/scp como hasta ahora.

---

## 4. Deploy VPS + migrate (nombre nuevo en push y página web)

Ya está desplegado lo de notas/citas/versión. Este paso es **solo** el rename y
la migración `administracion.0004`.

1. Copia al VPS, como en deploys anteriores:
   - `backend/apps/common/paginas.py`
   - `backend/apps/mensajeria/push/fcm.py`
   - `backend/apps/administracion/migrations/0004_mensaje_asis_messenger.py`
2. Rebuild `backend worker beat` (no toques Redis ni `.env`).
3. Migrate:

```bash
cd /opt/asiscole-canal
docker compose -f docker-compose.prod.yml exec backend python manage.py migrate administracion
```

4. Comprueba:

```powershell
curl.exe -sS https://jeanpiaget.asiscole.com/canal-api/health
curl.exe -sS "https://jeanpiaget.asiscole.com/canal-api/v0.1/sistema/version-app?plataforma=android"
curl.exe -sS https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta | Select-String "Asis Messenger"
```

Esperado: health `ok` + `fcm_disponible: true`; version-app `min_soportada` 1,
`ultima_disponible` 2, mensaje con **Asis Messenger**; HTML de eliminar-cuenta
con el nombre nuevo.

Jean Piaget SIE no se toca. Academy ya manda notas/citas.

---

## 5. APK firmado, desinstalar la vieja, probar en un teléfono

La debug de hoy **no** sirve para el colegio: otra firma. Hay que **desinstalar**
Asiscole Messenger / la debug y luego instalar la release.

```powershell
cd frontend/mobile
.\tool\build_apk.ps1
# → build\app\outputs\flutter-apk\Asis_Messenger.apk
```

En el teléfono:

1. Ajustes → Apps → Asiscole Messenger (o la debug) → Desinstalar. No basta
   «actualizar encima».
2. Instalar `Asis_Messenger.apk`. El icono debe decir **Asis Messenger**.
3. Login con un apoderado de prueba (Academy y, si aplica, Jean Piaget).
4. Push: entrada o nota → llega notificación con título Asis Messenger.
5. Pestaña **Notas**: semana, carrera, área.
6. Crear una **cita nueva** en Academy (Ctrl+F5 en el SIE) → aviso en Mensajes.
7. Perfil → Eliminar mi cuenta (en un usuario de prueba, no en uno real).
8. Abrir en el Chrome del teléfono:
   `https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta`

---

## 6. AAB + símbolos Crashlytics

```powershell
cd frontend/mobile
.\tool\build_aab.ps1
# → build\app\outputs\bundle\release\app-release.aab
# → build\app\outputs\symbols
```

Sube los símbolos de Dart ofuscado (el script imprime el comando). Necesitas
Firebase CLI y el `ANDROID_APP_ID` de la consola Firebase (no es el
applicationId):

```powershell
firebase crashlytics:symbols:upload --app=<ANDROID_APP_ID> build\app\outputs\symbols
```

En Play Console, al crear la versión, adjunta también esos símbolos (Android
vitals). Sin ellos un crash ofuscado es ilegible.

Crashlytics en debug está apagado a propósito. Solo el AAB/APK release reporta
fallos. No usa el teléfono como identificador.

---

## 7. Play Console — internal testing

Crea la app con el mismo applicationId `pe.asiscole.asiscole_app`.

**Ficha**

- Nombre: Asis Messenger
- Idioma: español (Perú)
- Descripción corta / larga: canal del colegio para avisos de entrada, salida,
  incidencias, citas y notas. Las credenciales las entrega el colegio; no hay
  registro autoservicio.
- Categoría: Educación / productividad
- Correo de contacto: el del paso 0 (el que sí recibe)
- Política de privacidad: URL **pública** HTTPS (hoy no existe; hay que
  publicar `docs/privacidad-y-tiendas.md` o una página equivalente)
- Icono 512 px, gráfico 1024×500, mínimo 2 capturas de teléfono
- Público: **adultos (apoderados)**. No es app infantil / Families Policy,
  aunque trate datos de menores.

**Notas de revisión (imprescindible)**

```
Login: teléfono del apoderado + documento del estudiante (codigo de barras /
DNI escolar). No hay alta pública. Cuenta de prueba:

Teléfono: <E.164 de un apoderado de prueba>
Documento: <codigo_barras del estudiante de prueba>
Colegio de demostración: Academy (demostracion.asisacademy.com)

URL eliminación de cuenta:
https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta
```

**Data Safety** (coherente con el código)

- Recogéis: teléfono del apoderado, token de push (identificador de
  dispositivo), mensajes cacheados en el teléfono, diagnóstico Crashlytics.
- No publicidad, no venta, no compartir con terceros.
- Cifrado en tránsito (HTTPS).
- Los datos **no** se respaldan en Drive (`allowBackup=false`).
- Eliminación: botón en Perfil + URL web de arriba.

**Internal testing:** súbete tú y 2–3 teléfonos del colegio. No pases a
producción hasta 48 h sin crashes raros.

---

## 8. Aviso al colegio (texto listo para WhatsApp / correo)

```
A partir de ahora la app se llama Asis Messenger.

1. Desinstalen la app vieja (Asiscole Messenger). No actualicen encima:
   la firma cambió y Android no la reemplaza.
2. Instalen el APK nuevo que les enviamos, o únanse a la prueba interna de Play
   cuando les mandemos el enlace.
3. Vuelvan a iniciar sesión con el mismo teléfono y el documento del estudiante.
4. Si no les llegan avisos, revisen que las notificaciones de Asis Messenger
   estén activas.

Soporte: <correo del paso 0>
Borrar cuenta: https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta
```

Sideload y Play no se actualizan entre sí. Quien instale por APK y luego por
Play tendrá que desinstalar otra vez.

---

## Qué no hay que hacer

- No cambiar `applicationId` ni el paquete `pe.asiscole.asiscole_app`.
- No tocar SIE Jean Piaget.
- No subir `min_soportada` por encima de 1 mientras haya padres con el APK
  1.0.0+1: los deja fuera.
- No rotar `DJANGO_SECRET_KEY` en este deploy (invalida todas las sesiones).
- No hacer `git add -A`.
- No firmar el APK del colegio con la clave de debug.
