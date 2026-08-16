# Fase 7 — Versiones, actualizaciones y reporte de fallos (diseño)

Fecha: 2026-08-13. **Es un diseño, no una implementación.** No he tocado código de
producto en esta fase. Si lo apruebas, va en un PR aparte.

## El problema que resuelve

Hoy la app es `1.0.0+1` y no tiene forma de saber que existe una versión más nueva,
ni el backend forma de exigir una mínima. Mientras el reparto es por APK y hay dos
colegios, se puede vivir con eso. Cuando la distribución sea Play, dejará de ser
verdad: convivirán versiones durante semanas y una parte de los usuarios no
actualizará nunca por su cuenta.

El caso concreto que ya está sobre la mesa: el día que se corrija un formato de
respuesta o se retire un endpoint, los clientes viejos empezarán a fallar de forma
opaca. Hoy la app traduciría eso a «Ocurrió un error inesperado» y el apoderado
llamaría al colegio.

## 1. Convención de versiones

`MAJOR.MINOR.PATCH+versionCode` en `pubspec.yaml`, con el `versionCode` siempre
creciente y sin reutilizar (Play lo rechaza y no admite volver atrás).

- **PATCH** — correcciones que no cambian el contrato: `1.0.1+2`.
- **MINOR** — funcionalidad nueva compatible, p. ej. activar Notas: `1.1.0+5`.
- **MAJOR** — la app deja de funcionar con versiones anteriores del canal, o al
  revés. Es el único caso que debería subir `min_soportada`.

Regla práctica: `min_soportada` solo se mueve cuando el backend rompe algo de verdad.
Bloquear una app que funciona es la peor experiencia posible para un apoderado que
solo quiere ver si su hijo entró al colegio.

## 2. Origen de la verdad: tabla central

Igual que los feature flags, que ya viven en una tabla y no en `settings`
(`listar_flags` en `backend/apps/administracion/services.py`), la versión va en la
central para poder cambiarla sin redespliegue.

Tabla `asis_app_version`, una fila por plataforma:

| columna | tipo | notas |
| --- | --- | --- |
| `plataforma` | texto, PK | `android`, `ios` |
| `min_soportada` | entero | `versionCode` mínimo que el canal admite |
| `ultima_disponible` | entero | `versionCode` publicado en la tienda |
| `version_nombre` | texto | `1.2.0`, solo para mostrar |
| `notas` | texto, nulo | «Qué hay de nuevo», opcional |
| `actualizado_en` | timestamp | auditoría |

El prefijo `asis_` cumple la regla del esquema legado. La comparación se hace por
`versionCode` entero, no por cadena semver: comparar `"1.10.0"` con `"1.9.0"` como
texto es un error clásico y aquí no hace falta arriesgarse.

## 3. Contrato (primero en OpenAPI)

`GET /v0.1/sistema/version-app?plataforma=android`

```json
{
  "min_soportada": 1,
  "ultima_disponible": 3,
  "version_nombre": "1.1.0",
  "actualizacion_obligatoria": false,
  "notas": "Mejoras de rendimiento"
}
```

Dos decisiones que importan:

- **Sin autenticación.** Es el único endpoint del canal que debe ser público, y por
  una razón concreta: si la app está por debajo del mínimo, el usuario probablemente
  tampoco pueda iniciar sesión, así que la comprobación tiene que funcionar antes de
  tener token. No expone ningún dato personal. Lleva rate-limit por IP.
- **El servidor decide, el cliente no compara.** `actualizacion_obligatoria` lo
  calcula el backend a partir del `versionCode` que el cliente manda en la cabecera
  `X-App-Version`. Así la lógica se corrige en el servidor y no queda congelada en
  cada APK instalado.

Conviene añadir esa cabecera `X-App-Version` a todas las peticiones desde el
interceptor de Dio, no solo a esta. Permite ver la distribución de versiones en los
logs del canal (es un dato del dispositivo, no personal, así que no choca con la
regla de privacidad) y responder `426` de forma selectiva si alguna vez hace falta.

## 4. Comportamiento del cliente

En el arranque, en paralelo con la restauración de sesión y **sin bloquear la
interfaz**:

- Si `actualizacion_obligatoria` es verdadero → pantalla de bloqueo a pantalla
  completa, con un botón que abre Play y sin manera de saltarla. El texto debe decir
  qué pasa y qué hacer, no «versión no soportada».
- Si hay una versión más nueva pero no es obligatoria → aviso descartable, como
  máximo una vez cada 48 horas, guardando la marca en `SharedPreferences`.
- **Si la llamada falla o no hay red → no molestar y seguir.** Es la regla más
  importante de las cuatro: un fallo del endpoint de versión nunca debe impedir usar
  la app, sobre todo cuando el modo offline es una función anunciada del producto.
  Falla abierto, al contrario que el rate-limit de login, que falla cerrado.

## 5. `in_app_update` en Android

El paquete `in_app_update` solo funciona con builds instalados desde Play, así que
esto llega cuando llegue la publicación. Con la distribución por APK actual no hace
nada y hay que degradar a abrir la ficha de Play.

- `actualizacion_obligatoria` → flujo **immediate** (Play toma la pantalla y
  actualiza).
- Actualización opcional → flujo **flexible** (descarga en segundo plano y pide
  reiniciar).

El bloqueo propio del punto 4 se queda de todas formas: es la red de seguridad para
los APK repartidos a mano, que `in_app_update` no puede tocar.

## 6. Crashlytics

Es el hueco que más pesa de la Fase 6, porque el build ya es ofuscado: sin símbolos
subidos, un crash es ilegible.

- `firebase_crashlytics` en `pubspec.yaml`, `FlutterError.onError` y
  `PlatformDispatcher.instance.onError` enganchados en `main()`.
- Subir los símbolos de `--split-debug-info` (`build/app/outputs/symbols`) en cada
  release. El script de build ya los genera y guarda, que es la mitad del trabajo.
- **Cuidado con la privacidad, y no es un detalle menor.** Crashlytics no debe
  recibir teléfonos, `codigo_barras`, nombres ni texto de mensajes. Concretamente:
  no usar `setUserIdentifier` con el teléfono (si hace falta correlacionar, el
  `device_id`, que ya es un identificador interno), y no volcar cuerpos de respuesta
  en las claves personalizadas. Lo útil y seguro es `tenant`, `versionCode`,
  `request_id` y el código de error.
- Declararlo en Data Safety como datos de diagnóstico.

## 7. Checklist de release (a documentar en `docs/`)

1. Subir `version` y `versionCode` en `pubspec.yaml`.
2. `flutter analyze` y `flutter test` en verde.
3. `flutter build appbundle --release --obfuscate --split-debug-info=…` firmado con
   el keystore de release.
4. Subir símbolos a Crashlytics y a Play.
5. Internal testing → closed testing con apoderados reales.
6. Producción con rollout al 5-10 %; vigilar Android vitals 48 horas.
7. Si todo bien, ampliar al 100 % y actualizar `ultima_disponible` en
   `asis_app_version`.
8. Si mal: pausar el rollout; y solo mover `min_soportada` cuando la versión
   corregida ya esté publicada y disponible.

## Orden que yo seguiría

Crashlytics primero, porque sin él el rollout escalonado es a ciegas y no sirve de
nada ir despacio si no vas a ver lo que pasa. El endpoint de versión y la pantalla de
bloqueo después, antes de la primera publicación en Play. `in_app_update` al final,
cuando ya haya una segunda versión que actualizar.

Dime si lo implemento y en qué orden.
