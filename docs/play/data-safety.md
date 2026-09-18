# Data Safety — Asis Messenger

Respuestas para el formulario de Play Console. Deben coincidir con el código. Si cambia el tratamiento, actualiza este archivo **antes** de la ficha.

Público: **adultos (apoderados)**. No es app infantil. Recoge datos vinculados a menores solo para informar al padre, madre o tutor.

## Recopilación de datos — Sí

### Información personal

| Tipo | Recogido | Obligatorio | Finalidad | Compartido |
| --- | --- | --- | --- | --- |
| Número de teléfono | Sí | Sí (login) | Funcionalidad de la app (cuenta) | No |

El teléfono del apoderado identifica la sesión. No se usa para publicidad.

### Mensajes

| Tipo | Recogido | Obligatorio | Finalidad | Compartido |
| --- | --- | --- | --- | --- |
| Otros contenidos del usuario (mensajes del colegio) | Sí | Sí | Funcionalidad (bandeja) | No |

Los mensajes los genera el servidor. La app guarda en el teléfono **solo** los ya recibidos. El apoderado puede borrar esa copia (Perfil → Borrar mensajes guardados) o al eliminar la cuenta.

### Identificadores de dispositivo

| Tipo | Recogido | Obligatorio | Finalidad | Compartido |
| --- | --- | --- | --- | --- |
| Identificadores de dispositivo u otros (token FCM) | Sí | No (sin él no hay push) | Funcionalidad (notificaciones) | No (solo Google FCM para entregar el aviso; el payload no lleva datos del menor) |

### Datos de diagnóstico

| Tipo | Recogido | Obligatorio | Finalidad | Compartido |
| --- | --- | --- | --- | --- |
| Informes de fallos | Sí (release) | No | Análisis / estabilidad (Crashlytics) | Con Google Firebase como encargado de tratamiento |

Crashlytics no registra teléfono, documento ni nombres de estudiantes.

## No se recogen

Ubicación, fotos, contactos, calendario, salud, finanzas, historial de navegación, identificadores de publicidad.

## Preguntas globales

| Pregunta | Respuesta |
| --- | --- |
| ¿Se recogen datos? | Sí |
| ¿Se venden datos? | No |
| ¿Se comparten con terceros con fines publicitarios? | No |
| ¿Cifrado en tránsito? | Sí (HTTPS) |
| ¿Los usuarios pueden solicitar que se eliminen los datos? | Sí |
| ¿Los datos se respaldan en el dispositivo / Drive? | No (`android:allowBackup="false"`) |

## Cómo se eliminan

1. En la app: Perfil → Eliminar mi cuenta (confirma con el documento del estudiante).
2. URL pública: https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta  
   (instrucciones + correo `trabajoandre4@gmail.com` si no puede entrar).

Efecto: se anonimiza el apoderado, se revocan sesiones, se apaga el push y se anonimizan sus mensajes en el canal. **No** se borra el expediente del colegio (asistencia, incidencias, matrícula).

## Permisos Android (coherencia)

`INTERNET`, `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS`. Ningún permiso de ubicación, cámara, contactos ni almacenamiento amplio.
