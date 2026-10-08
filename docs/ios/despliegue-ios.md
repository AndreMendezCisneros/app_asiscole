# Despliegue iOS con Codemagic

Guía para publicar Asis Messenger en iPhone. El build y la subida a TestFlight los hace
Codemagic con `codemagic.yaml` (raíz del repo). No hace falta Mac propia.

Alcance de la versión 1: solo iPhone, iOS 15 o superior. En iPad corre en modo compatibilidad
de iPhone; no se publica como app de iPad.

---

## 1. Qué ya está listo en el repo

| Pieza | Dónde |
|---|---|
| Push iOS por FCM (Firebase entrega a APNs) | `backend/apps/mensajeria/push/fcm.py`, desplegado |
| Política de versión `ios` en `asis_app_version` | migración `administracion/0004`, desplegada |
| La app consulta su plataforma y abre la App Store, nunca Play | `lib/core/version/` |
| Bundle `pe.asiscole.asiscoleApp`, nombre `Asis Messenger`, español | `ios/Runner/Info.plist` |
| Push: `aps-environment` y `remote-notification` | `Runner.entitlements`, `Info.plist` |
| Exportación: `ITSAppUsesNonExemptEncryption = false` (solo HTTPS) | `Info.plist` |
| Manifiesto de privacidad | `ios/Runner/PrivacyInfo.xcprivacy` |
| Solo iPhone, iOS 15 | `project.pbxproj`, `Podfile` |
| Caché de mensajes fuera del respaldo de iCloud | `AppDelegate.swift` |
| Keychain que no migra de equipo y se limpia al reinstalar | `lib/core/storage/secure_storage.dart` |
| Espera del token APNs antes de pedir el token FCM | `lib/core/push/servicio_push.dart` |
| Pipeline: pruebas, firma, IPA, dSYM y TestFlight | `codemagic.yaml` |

Lo que falta depende de cuentas: Apple Developer, Firebase y Codemagic. Va en orden.

---

## 2. Cuenta Apple Developer

1. Inscribir la organización en el Apple Developer Program (99 USD al año). Como
   organización hace falta número D-U-N-S; el trámite tarda días. Una cuenta personal
   publicaría la app con el nombre de una persona, no del colegio.
2. En **Certificates, Identifiers & Profiles → Identifiers**, crear el App ID
   `pe.asiscole.asiscoleApp` y marcar **Push Notifications**.
3. En **Keys**, crear una clave con **Apple Push Notifications service (APNs)**. Descargar
   el `.p8` (solo se descarga una vez) y anotar el **Key ID** y el **Team ID**.
4. En **App Store Connect → Apps → +**, crear la app:
   - Nombre: `Asis Messenger`
   - Idioma principal: Español (México); es el español latinoamericano que ofrece Apple.
   - Bundle ID: `pe.asiscole.asiscoleApp`
   - SKU: `asis-messenger-ios`
5. En **App Information** copiar el **Apple ID** numérico de la app. Va en
   `APP_STORE_APP_ID` de `codemagic.yaml` (hoy tiene `0000000000` y el build se niega a
   correr así).
6. En **Users and Access → Integrations → App Store Connect API**, crear una clave con rol
   **App Manager**. Descargar el `.p8` y anotar **Issuer ID** y **Key ID**. Es para
   Codemagic, distinta de la de APNs.

## 3. Firebase

El proyecto Firebase es el mismo de Android.

1. **Configuración del proyecto → Tus apps → Agregar app → iOS** con el bundle
   `pe.asiscole.asiscoleApp`. Descargar `GoogleService-Info.plist`.
2. **Cloud Messaging → Configuración de apps de Apple → Clave de autenticación de APNs**:
   subir el `.p8` de APNs con su Key ID y Team ID. Sin esto el backend envía y Firebase
   responde bien, pero el iPhone no recibe nada.
3. Regenerar `firebase_options.dart` con la rama iOS (desde `frontend/mobile`, sirve en
   Windows):

   ```powershell
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<id-del-proyecto> --platforms=android,ios `
     --ios-bundle-id=pe.asiscole.asiscoleApp --android-package-name=pe.asiscole.asiscole_app
   ```

   Si `flutterfire` toca `android/app/build.gradle` o crea `firebase.json`, revisar el diff
   antes de aceptar: Android ya funciona y no debe cambiar.
4. Guardar los dos archivos reales en `secrets/secrets/` (fuera de Git):
   `firebase_options.dart` y `GoogleService-Info.plist`. Comprobar con:

   ```powershell
   .\tool\ensure_firebase.ps1 -Ios
   ```

   El script falla si `firebase_options.dart` no tiene la rama iOS o si falta el plist.

## 4. Codemagic

1. Entrar a Codemagic con la cuenta de GitHub y agregar el repo
   `AndreMendezCisneros/app_asiscole`. Elegir configuración por `codemagic.yaml`.
2. **Team settings → Integrations → Developer Portal**: agregar la clave API de App Store
   Connect con el nombre exacto **`Asiscole ASC`** (es el que usa el YAML).
3. **Team settings → Code signing identities**:
   - **iOS certificates → Generate certificate**, tipo *Apple Distribution*, con la
     integración anterior. Guardar la contraseña que muestra.
   - **iOS provisioning profiles → Fetch profiles**: traer o crear el perfil *App Store*
     de `pe.asiscole.asiscoleApp`. Debe incluir Push Notifications; si el perfil se creó
     antes de marcar Push en el App ID, borrarlo y volver a crearlo.
4. **App → Environment variables**, grupo **`firebase_ios`**, ambos marcados como *Secret*:

   | Variable | Valor |
   |---|---|
   | `FIREBASE_OPTIONS_DART_B64` | `firebase_options.dart` en base64 |
   | `GOOGLE_SERVICE_INFO_PLIST_B64` | `GoogleService-Info.plist` en base64 |

   Para sacar el base64 en Windows (desde la raíz del repo; queda en el portapapeles):

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("secrets\secrets\firebase_options.dart")) | Set-Clipboard
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("secrets\secrets\GoogleService-Info.plist")) | Set-Clipboard
   ```

5. Poner el Apple ID numérico en `APP_STORE_APP_ID` de `codemagic.yaml` y subir el cambio.

## 5. Lanzar un build

- **Manual:** Codemagic → la app → *Start new build* → workflow `ios-testflight`.
- **Por tag:** `git tag ios-v1.1.0 && git push origin ios-v1.1.0`.

Qué hace el workflow, en orden:

1. Restaura `firebase_options.dart` y el plist desde los secretos y verifica que sean de
   iOS y del bundle correcto.
2. `flutter pub get` y `pod install` (CocoaPods; Swift Package Manager desactivado para
   que la herramienta de dSYM de Crashlytics quede en `Pods/`).
3. `flutter analyze` y `flutter test`. Si fallan, no se firma nada.
4. Firma con el perfil App Store.
5. `flutter build ipa` con `ASISCOLE_ENV=prod`, Dart ofuscado y símbolos aparte.
6. Sube los dSYM a Crashlytics.
7. Publica en TestFlight.

**Versión y build.** La versión visible (`1.1.0`) sale de `pubspec.yaml`. El build number
lo calcula el pipeline: último de TestFlight más uno. Por eso en iOS empieza en 1 y no
coincide con el `versionCode` de Android; la política de versión del backend es por
plataforma, así que no se mezclan.

**Símbolos Dart.** Quedan como artefacto (`build/ios/symbols`). Para que Crashlytics
desofusque los errores Dart:

```powershell
firebase crashlytics:symbols:upload --app=<IOS_APP_ID_DE_FIREBASE> <carpeta-symbols>
```

## 6. Pruebas en TestFlight

En **App Store Connect → TestFlight → Internal Testing**, crear un grupo (por ejemplo
`Colegio`) con descarga automática y agregar a los testers. Lo reciben sin revisión de
Apple.

Antes de mandar a revisión, en un iPhone real:

- [ ] Login con teléfono y documento; el segundo login en otro equipo se deniega (409)
- [ ] Aceptar el permiso de notificaciones al primer arranque
- [ ] Push con la app abierta, en segundo plano y cerrada
- [ ] Tocar el push abre el mensaje correcto
- [ ] Modo avión: se leen los mensajes cacheados y nada más
- [ ] Cerrar sesión y volver a entrar
- [ ] Eliminar cuenta desde Perfil
- [ ] Desinstalar y reinstalar: pide login de nuevo (no revive la sesión)
- [ ] Modo oscuro y tamaño de letra grande del sistema

## 7. Revisión de Apple

En la ficha de App Store Connect:

- **App Privacy (nutrition labels):** teléfono, identificador de dispositivo y contenido de
  los mensajes, ligados al usuario, para funcionalidad de la app; datos de diagnóstico (crashes) sin ligar. Sin
  rastreo. Debe coincidir con `PrivacyInfo.xcprivacy` y con
  `docs/privacidad-y-tiendas.md`.
- **Clasificación por edad:** la app se dirige a apoderados adultos.
- **URL de privacidad y de soporte:** las mismas de la ficha de Play.
- **App Review Information:** cuenta de demostración (documento `80000001` del estudiante
  de prueba, con el teléfono de apoderado que tenga registrado; datos ficticios) y una nota que explique que no hay registro
  público: el colegio entrega los datos de acceso y el login es teléfono del apoderado
  más documento del estudiante. Sin la cuenta de demostración, Apple rechaza.
- **Eliminación de cuenta:** indicar la ruta en la app (Perfil → Eliminar cuenta).
- **Cifrado de exportación:** ya respondido en el `Info.plist`; App Store Connect no lo
  vuelve a preguntar.

## 8. Después de publicar

Con la ficha pública, apuntar la política de versión iOS del canal a la App Store para que
el botón *Actualizar* la abra:

```bash
docker exec -it asiscole_canal_backend python manage.py shell -c \
  "from apps.administracion.models import VersionApp; \
   VersionApp.objects.filter(plataforma='ios').update(url_tienda='https://apps.apple.com/app/id<APPLE_ID>')"
```

Mientras `url_tienda` esté vacía, la app iOS no ofrece actualizar (en iOS nunca cae a la
ficha de Play). Para avisar de un build nuevo se sube `ultima_disponible` de la fila `ios`;
para obligar a actualizar, `min_soportada`. Ambos son build numbers de iOS, no de Android.

## 9. Problemas frecuentes

| Síntoma | Causa probable |
|---|---|
| El build falla en "Restaurar configuración Firebase" | Falta un secreto del grupo `firebase_ios` o el plist es de otro bundle |
| `No matching profiles found` | El perfil App Store no existe o no se trajo en Codemagic |
| `Provisioning profile doesn't include the aps-environment entitlement` | El perfil se creó antes de activar Push en el App ID; regenerarlo |
| El iPhone no recibe push pero el backend registra el envío | Falta la clave `.p8` de APNs en Firebase Cloud Messaging |
| `ITMS-91053: Missing API declaration` | Un plugin nuevo usa una API sensible; declararla en `PrivacyInfo.xcprivacy` |
| Subida rechazada por build number repetido | `APP_STORE_APP_ID` mal puesto: no encuentra builds previos y usa 1 |
