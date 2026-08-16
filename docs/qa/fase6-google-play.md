# Fase 6 — Checklist de publicación en Google Play

Fecha: 2026-08-13. Estado verificado sobre el repositorio, sin ejecutar nada en
Play Console. Complementa la checklist de
[`privacidad-y-tiendas.md`](../privacidad-y-tiendas.md) §6, que cubre la parte
legal; esta cubre la parte técnica y operativa.

Leyenda: `[ok]` verificado en el repo · `[falta]` bloquea la publicación ·
`[pend]` depende de ti o de Play Console.

## Artefacto

- `[ok]` **AAB.** `tool/build_aab.ps1` genera el App Bundle firmado y ofuscado, con
  símbolos en `build/app/outputs/symbols`. `tool/build_apk.ps1` sigue existiendo
  para el reparto por sideload.
- `[pend]` **Firma de release.** El build de release ya **falla** si no existe
  `android/key.properties`, en vez de caer a la clave de depuración (F1-02, S-01).
  Falta que generes el keystore, que es un secreto tuyo:

```powershell
keytool -genkeypair -v -keystore frontend/mobile/android/keystore/asiscole-release.jks `
  -keyalg RSA -keysize 4096 -validity 10000 -alias asiscole
Copy-Item frontend/mobile/android/key.properties.example frontend/mobile/android/key.properties
# y completar keyAlias / keyPassword / storePassword / storeFile
```

  El `.jks` y `key.properties` ya están en `.gitignore`. Guarda una copia fuera del
  equipo: si se pierde la clave de carga, Play obliga a publicar una app nueva.
- `[pend]` **Play App Signing.** Al subir el primer bundle, Play pide la clave de
  carga. Decidir si se deja que Play gestione la clave de firma (recomendado) y
  guardar la de carga con copia de seguridad fuera del equipo: perderla obliga a
  publicar una app nueva.
- `[ok]` **Ofuscación y símbolos.** El build ya usa `--obfuscate` con
  `--split-debug-info` en `build/app/outputs/symbols`, y R8 con `isMinifyEnabled` y
  `isShrinkResources`. Los símbolos hay que subirlos a Play en cada versión para que
  los stack traces sean legibles.
- `[pend]` **targetSdk.** El proyecto hereda `flutter.targetSdkVersion` (Flutter
  3.41.9), no lo fija a mano. Antes de subir, confirmar el valor efectivo contra el
  mínimo que Play exija en ese momento:
  `flutter build appbundle --release` y revisar
  `build/app/intermediates/merged_manifests/release/AndroidManifest.xml`.
- `[ok]` **minSdk 23**, justificado por `flutter_secure_storage` y
  `firebase_messaging`. Cubre la práctica totalidad del parque real en Perú.
- `[ok]` **Permisos mínimos:** `INTERNET`, `ACCESS_NETWORK_STATE`,
  `POST_NOTIFICATIONS`. Ninguno que obligue a justificación en el formulario de
  permisos sensibles.
- `[ok]` **Identidad:** `applicationId` `pe.asiscole.asiscole_app`, etiqueta
  «Asis Messenger», icono adaptativo configurado con `flutter_launcher_icons`.
- `[ok]` **Respaldo desactivado.** `android:allowBackup="false"` más
  `res/xml/data_extraction_rules.xml`, que excluye todo del respaldo en la nube y de
  la transferencia entre dispositivos (S-02). En Data Safety se puede declarar que
  los datos **no** se respaldan.

## Estabilidad y observabilidad

- `[falta]` **Crash reporting.** No hay Crashlytics (F1-03). Publicar una app
  ofuscada sin reporte de crashes deja ciegos a los Android vitals: si el ANR rate o
  el crash rate suben, no habrá forma de saber por qué. Diseño en la Fase 7.
- `[ok]` **Suite verde.** `flutter test` pasa 16/16 y `flutter analyze` no reporta
  nada, tras hacer determinista `parseInstanteApi` (F1-01).
- `[pend]` **Android vitals.** Definir el umbral de pausa del rollout antes de
  empezar (por ejemplo, crash rate por encima del 1 % de sesiones).

## Contenido de la ficha

- `[pend]` Descripción corta y larga en español, explicando que las credenciales las
  entrega el colegio (si no, el revisor no podrá entrar).
- `[pend]` **Cuenta de prueba para el revisor**, con teléfono y documento válidos de
  un estudiante de prueba, en las notas de revisión. Sin esto el rechazo es casi
  seguro: el login no es autoservicio.
- `[pend]` Capturas de teléfono (mínimo dos), icono de 512 px, gráfico destacado de
  1024 × 500.
- `[pend]` Categoría, correo de contacto y política de privacidad en URL pública.
- `[pend]` **Data Safety** coherente con el comportamiento real: teléfono del
  apoderado, identificador de dispositivo (token de push), contenido de mensajes
  cacheado en el dispositivo, y —si no se corrige S-02— respaldo en la nube. Nada de
  publicidad, nada de compartir con terceros, datos cifrados en tránsito.
- `[pend]` **Eliminación de cuenta.** Play exige que sea accesible desde la app y,
  además, por una URL web. Dentro de la app ya existe (Perfil → «Eliminar mi
  cuenta»); falta la página web y corregir que la eliminación no borra la caché
  local ni anonimiza los mensajes (F1-05, S-03).
- `[pend]` **Clasificación por edad y público objetivo.** Declarar que la app se
  dirige a **adultos** (apoderados), no a menores, para no entrar en Families
  Policy. El hecho de que trate datos de menores no la convierte en app infantil,
  pero el cuestionario hay que responderlo con cuidado.
- `[falta]` **Pestaña «Notas» vacía** (Hueco 3 de la Fase 2). Una pestaña permanente
  que nunca muestra contenido puede leerse como funcionalidad incompleta. Ocultarla
  mientras el flag esté apagado.

## Despliegue

- `[pend]` **Internal testing** primero, con los teléfonos del colegio y del equipo.
- `[pend]` **Closed testing** con un grupo real de apoderados de Jean Piaget, que es
  el tenant estable.
- `[pend]` **Producción con rollout escalonado** al 5-10 %. Además de reducir el
  riesgo de una regresión, es la mejor mitigación del pico de login del primer día
  que quedó sin medir en la Fase 4.
- `[pend]` **Plan de vuelta atrás.** Documentar los dos casos, que no se arreglan
  igual:
  - Fallo de la app → pausar el rollout en Play Console y publicar una versión
    corregida. Play no permite volver a un `versionCode` anterior.
  - Fallo de la API → redespliegue del VPS
    (`bash scripts/ops_prod_cutover.sh`), que es inmediato y no depende de Play.
    Esto es una ventaja del diseño: el texto de los mensajes lo genera el backend,
    así que buena parte de los errores de producto se corrigen sin tocar el cliente.
- `[pend]` **Comunicación al colegio** de que a partir de la publicación conviven
  varias versiones en campo, y que sin el control de versión mínima (F1-04) no hay
  manera de forzar una actualización.

## Resumen

Bloquean la publicación cuatro cosas, todas de infraestructura de release y no de
producto: **AAB**, **firma de release**, **suite de pruebas en verde** y
**Crashlytics**. Las tres primeras son de horas; la cuarta es la Fase 7.

Fuera de eso, `allowBackup` y la pestaña Notas vacía son las dos que yo corregiría
antes de subir, porque una afecta a lo que hay que declarar en Data Safety y la otra
a lo que verá el revisor.
