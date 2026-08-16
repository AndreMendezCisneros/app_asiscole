# Fase 1 — Auditoría estática (app + backend)

Auditoría QA pre-lanzamiento. Fecha: 2026-08-13. Rama `master`, commit base `3a711f6`.
Formato por hallazgo: **severidad · evidencia · recomendación**. Sin cambios de código.

## Verificación ejecutada

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` | 4 avisos: 1 `warning` (`unused_import`), 3 `info` |
| `flutter test` | **13 pruebas, 1 falla** (`formato_lima_test.dart`) |
| `pytest` (backend) | 149 pruebas, todas pasan |
| `android/key.properties` | **no existe** → release firmado con clave de debug |
| `firebase_crashlytics` en `pubspec.yaml` | **ausente** |

---

## F1-01 · Prueba en rojo por fecha fija, y el parseo de horas depende del reloj

**Severidad: alta.**

`flutter test` falla en «parseInstanteApi corrige UTC etiquetado como Lima (-05)»:
esperaba hora `18`, obtuvo `23`.

La corrección de `parseInstanteApi` solo se activa si el instante resultante queda
más de dos horas **en el futuro**:

```126:126:frontend/mobile/lib/core/util/formato.dart
    if (absoluto.difference(ahora) > const Duration(hours: 2)) {
```

El caso de prueba usa la fecha fija `2026-07-27`, que hoy ya es pasado, así que la
heurística no entra. Son dos problemas en uno:

- La suite de la app queda roja de forma permanente, y con ella cualquier control
  de calidad previo al release.
- El mismo valor de `emitido_en` se interpreta distinto según **cuándo** se lea. Un
  mensaje que el VPS legacy etiquete como `18:47:52-05:00` se corrige si se lee en
  caliente, pero se muestra con cinco horas de más si se lee dos horas después o
  desde la caché local.

**Recomendación.** Quitar la dependencia del reloj: normalizar el instante en el
backend (que `emitido_en` salga siempre con sufijo `Z`) y dejar en el cliente un
parseo determinista. Si se conserva la heurística como red de seguridad, inyectar
el "ahora" como parámetro para poder probarla, y usar fechas relativas en el test.

## F1-02 · No hay firma de release: el artefacto actual no es publicable

**Severidad: alta (bloquea Google Play).**

```59:73:frontend/mobile/android/app/build.gradle.kts
    buildTypes {
        release {
            // Si existe key.properties → firma release; si no, debug (solo local).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
```

`frontend/mobile/android/key.properties` no existe en la máquina de build, así que
el APK que hoy se distribuye va firmado con la clave de depuración. Play rechaza
ese artefacto. Además Play exige **AAB**, y `scripts/ops_local_release.ps1` produce
un APK (correcto para sideload, no para la ficha de Play).

**Recomendación.** Crear el keystore de release, guardarlo fuera del repositorio,
completar `key.properties` desde el `.example` y añadir un objetivo de build que
genere `appbundle`. El APK sideload puede seguir existiendo en paralelo.

## F1-03 · Sin reporte de crashes en una app ofuscada

**Severidad: alta.**

`pubspec.yaml` no incluye `firebase_crashlytics` ni equivalente, y el release
aplica ofuscación Dart más R8 (`isMinifyEnabled = true`). Un cierre inesperado en
el teléfono de un apoderado hoy no deja rastro recuperable: no hay stack trace, no
hay `versionCode`, y el símbolo está ofuscado.

**Recomendación.** Añadir Crashlytics antes del primer rollout y subir los símbolos
de depuración en cada build. Se detalla en la Fase 7.

## F1-04 · No existe control de versión mínima del cliente

**Severidad: alta.**

`version: 1.0.0+1` y ningún endpoint que informe qué versión soporta el canal. Ya
hubo un incidente de este tipo: al rotar `DJANGO_SECRET_KEY` en el cutover, los
APK antiguos quedaron con sesión inválida y la única vía fue avisar a los
apoderados de palabra para que borraran los datos de la app
(`docs/estado-produccion.md` §4). Con la app en Play y varias versiones en campo
a la vez, ese escenario se repite sin manera de forzar la actualización.

**Recomendación.** Diseño en la Fase 7 (endpoint de versión + bloqueo por
`min_soportada` + `in_app_update`).

## F1-05 · El apoderado no puede borrar la caché local de mensajes

**Severidad: media (privacidad, Ley 29733).**

La política dice que la caché del dispositivo «la borra el apoderado»
(`docs/privacidad-y-tiendas.md` §3 y la regla `datos-menores`). El método existe:

```155:159:frontend/mobile/lib/core/storage/local_db.dart
  Future<void> vaciar() async {
    final db = await database;
    await db.delete(tablaMensajes);
    await db.delete(tablaLeidosPendientes);
  }
```

pero no se invoca desde ninguna pantalla: en `lib/` no hay una sola llamada a
`vaciar()`. En `PerfilPage` hay «Cerrar sesión» y «Eliminar mi cuenta», y ninguna
de las dos toca la base local (el propio `SessionStorage.limpiarTokens` documenta
que la caché de mensajes no se toca). El texto de los mensajes y el nombre del
estudiante quedan en SQLite sin cifrar hasta que se desinstale la app.

**Recomendación.** Añadir «Borrar mensajes guardados en este teléfono» en Perfil, y
vaciar la caché al eliminar la cuenta (ahí sí es obligatorio: es el ejercicio del
derecho de cancelación).

## F1-06 · Un 403 sin cuerpo JSON hace que la app declare la cuenta suspendida

**Severidad: media.**

Cuando la respuesta de error no trae el campo `code` del contrato, la app deduce
el código del estado HTTP:

```68:79:frontend/mobile/lib/core/error/api_error.dart
  static String _codigoPorEstado(int? status) => switch (status) {
        400 => CodigosError.validacion,
        401 => CodigosError.noAutenticado,
        403 => CodigosError.cuentaSuspendida,
        404 => CodigosError.vinculoNoEncontrado,
```

Un 403 generado por el proxy (Caddy, un WAF, una regla de Cloudflare si algún día
se activa) devuelve HTML, no JSON. La app lo traduce a `ACCOUNT_SUSPENDED`, y ese
código en el interceptor termina en `_sesionInvalidada`, que borra los tokens y
emite `Suspended`: el apoderado ve «tu cuenta está suspendida» y pierde la sesión
por un problema de infraestructura. Lo mismo, más leve, con 404 → «no encontramos
el vínculo».

**Recomendación.** Para 403 y 404 sin `code` en el cuerpo, usar un código genérico
de error y reservar `ACCOUNT_SUSPENDED` / `STUDENT_LINK_NOT_FOUND` a las
respuestas que sí vengan del canal.

## F1-07 · Las claves de Firebase del cliente conviven con el repositorio

**Severidad: media (proceso, no exposición).**

`frontend/mobile/lib/firebase_options.dart` está versionado en git y en el working
copy contiene los valores reales del proyecto `asiscole-canal` (`apiKey`, `appId`,
`messagingSenderId`), en estado modificado sin commitear. No es un secreto de
servidor —esos valores viajan dentro de cualquier APK— pero mezcla configuración
de entorno con el código, ya provocó un ida y vuelta de "restaurar el stub", y
convierte cada build en una fuente de ruido en `git status`.

**Recomendación.** Dejar en git únicamente `firebase_options.dart.example`,
ignorar el archivo real y seguir generándolo en build desde `secrets/` como ya
hace `tool/build_apk.ps1`.

## F1-08 · La sincronización se corta a las cinco páginas

**Severidad: baja.**

```19:19:frontend/mobile/lib/features/mensajes/data/mensajes_repository.dart
  static const int _maxPaginasSync = 5;
```

El cliente pide `limit: 100` y el backend admite hasta 200 por página, así que el
techo real es de 500 mensajes por sincronización. Con dos hijos y cuatro avisos
diarios eso cubre unos seis meses de historial, de modo que el corte no se alcanza
en uso normal. Queda anotado porque si se alcanza no hay señal en la interfaz: una
bandeja truncada se ve igual que una bandeja completa.

**Recomendación.** No tocar el límite. Si en el futuro se añaden tipos de aviso
más frecuentes, exponer un «cargar más antiguos» en lugar de subir el tope.

## F1-09 · Avisos pendientes de `flutter analyze`

**Severidad: baja.**

Un `warning` de import sin usar en `lib/core/config/env.dart:1` y tres `info`
(`prefer_interpolation_to_compose_strings` en `formato.dart:135`,
`use_null_aware_elements` en `mensajes_api.dart:19-20`). No afectan al
comportamiento; conviene llegar a cero antes de publicar para que el análisis
sirva como señal.

## F1-10 · La IP de origen depende de que haya exactamente un proxy

**Severidad: baja (riesgo de configuración futura).**

```40:45:backend/apps/cuentas/views.py
    reenviada = request.headers.get("X-Forwarded-For", "")
    if reenviada:
        partes = [p.strip() for p in reenviada.split(",") if p.strip()]
        if partes:
            return partes[-1]
```

Tomar el último salto es la decisión correcta con la topología actual (Caddy es el
único proxy y añade la IP real al final, así que un cliente no puede falsificarla).
Pero si se pone Cloudflare por delante, el último salto pasa a ser la IP del edge
de Cloudflare, compartida por todos los apoderados: el bloqueo por IP del
rate-limit se volvería prácticamente global (tres fallos de cualquiera bloquean a
todos cinco minutos, y ocho fallos, veinticuatro horas).

**Recomendación.** Dejarlo documentado como precondición de despliegue: si se
activa Cloudflare, pasar a `CF-Connecting-IP` o a un número de saltos de confianza
configurable.

---

## Lo que está bien y no hay que tocar

Vale registrarlo porque acota el alcance de las fases siguientes:

- **Capas y contrato.** `features/*/data|domain|presentation` con Cubit y GetIt, un
  único `ApiClient` con `Dio`, y el esquema de token declarado por endpoint
  (`EsquemaAuth.ninguno|sesion|datos`). El `session_token` no se usa nunca en
  endpoints de negocio.
- **Refresco de token.** El `Completer` de `AuthInterceptor._renovarUnaSolaVez`
  garantiza un solo `refresh-data` aunque fallen varias peticiones a la vez, y el
  reintento se marca para que no haya bucle. Hay pruebas que lo cubren.
- **Sesión.** Tokens y perfil solo en `flutter_secure_storage`; `device_id`
  generado localmente y sin datos personales.
- **Login opaco.** El backend responde siempre `STUDENT_LINK_NOT_FOUND` sin
  distinguir si falló el teléfono o el documento, y el detalle del serializer nunca
  se devuelve al cliente.
- **Sesión única.** La garantía es el índice único parcial de la base, no una
  comprobación en Python; la carrera entre dos logins simultáneos se resuelve con
  el mismo 409 que un segundo dispositivo.
- **Rate-limit fail-closed.** Si Redis no responde, `_asegurar_cache_auth` devuelve
  429 en lugar de dejar el login abierto. La credencial y la IP se guardan
  hasheadas, nunca en claro.
- **Logs.** DRF deniega por defecto (`DenegarPorDefecto`), el formatter JSON redacta
  cualquier `extra` cuyo nombre suene a dato personal, y `django.db.backends` está
  en `WARNING` para que no salgan consultas con datos.
- **Aislamiento.** El `estudiante_id` que manda el cliente siempre se contrasta con
  `asis_directorio` (`academico/authz.py`); no se filtra en la interfaz.
- **Cleartext.** `usesCleartextTraffic` solo en el manifest de debug; el release
  únicamente pide `INTERNET`, `ACCESS_NETWORK_STATE` y `POST_NOTIFICATIONS`.
