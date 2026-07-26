# Plan de pruebas

Casos que QA debe cubrir antes de liberar. Se priorizan los escenarios donde el sistema
puede fallar de forma silenciosa o exponer datos, no los caminos felices obvios.

---

## 1. Sesión única y transferencia

| # | Escenario | Resultado esperado |
|---|---|---|
| S-01 | Login correcto en el dispositivo A | 200, se emiten ambos tokens |
| S-02 | Login en B con la sesión de A viva | 409 `SESSION_ALREADY_ACTIVE`; la sesión de A sigue funcionando |
| S-03 | Reinstalar la app en A y volver a entrar | 200, sin pedir intervención del administrador |
| S-04 | Dos logins simultáneos desde dispositivos distintos | Solo uno gana; el otro recibe 409 |
| S-05 | B solicita transferencia y A aprueba | A pierde la sesión; B entra al reintentar |
| S-06 | B solicita transferencia y A rechaza | B sigue denegado |
| S-07 | B solicita y nadie responde en 5 minutos | 410 `TRANSFER_EXPIRED` |
| S-08 | B pide una cuarta transferencia en una hora | 429 `TOO_MANY_REQUESTS` |
| S-09 | El administrador fuerza el cierre | B puede entrar sin aprobación de A |

## 2. Tokens

| # | Escenario | Resultado esperado |
|---|---|---|
| T-01 | El `data_token` caduca con la sesión viva | La app lo refresca sola; el usuario no percibe nada |
| T-02 | Cinco peticiones fallan con 401 a la vez | Se dispara un solo refresh, no cinco |
| T-03 | Usar un `session_token` en un endpoint de negocio | 401; los tipos no son intercambiables |
| T-04 | Usar un `data_token` en `/auth/renew-session` | 401 |
| T-05 | Renovar dentro de la ventana de los días 7 a 10 | Token nuevo |
| T-06 | Renovar en el día 3 | Se devuelve el token vigente, sin rotar |
| T-07 | Cien renovaciones simultáneas | Se escalonan sin degradar el backend |

## 3. Suspensión

| # | Escenario | Resultado esperado |
|---|---|---|
| U-01 | Suspender con sesión activa | La siguiente llamada devuelve 403; la app muestra el motivo |
| U-02 | Login con la cuenta suspendida | 403 `ACCOUNT_SUSPENDED` |
| U-03 | Mensajes cacheados con la cuenta suspendida | Se conservan, no se borran |
| U-04 | Reactivar | Se permite un login nuevo; la sesión anterior no se restaura |

## 4. Seguridad y aislamiento

| # | Escenario | Resultado esperado |
|---|---|---|
| A-01 | Pedir asistencias de un estudiante de otro apoderado | 403 `ROLE_NOT_ALLOWED` |
| A-02 | Manipular `estudiante_id` en la query | 403; el backend valida contra el directorio |
| A-03 | Enviar un `tenant_id` de otro colegio | Se ignora; el colegio sale del directorio |
| A-04 | Seis intentos fallidos seguidos | 423 `ACCOUNT_LOCKED` durante 30 minutos |
| A-05 | Teléfono correcto con documento equivocado | 404, sin revelar cuál de los dos falló |
| A-06 | Revisar los logs tras un login | No aparece ningún teléfono, documento ni nombre |

## 5. Ingesta y mensajería

| # | Escenario | Resultado esperado |
|---|---|---|
| I-01 | Registrar una entrada en el colegio | Llega el push y el mensaje aparece en la bandeja |
| I-02 | Registrar la salida del mismo día | Segundo mensaje distinto del de entrada |
| I-03 | Corregir la hora de salida ya registrada | No se genera un aviso nuevo |
| I-04 | Ejecutar el poller dos veces sobre el mismo evento | Un solo mensaje; la idempotencia funciona |
| I-05 | Caer el servicio de push | La asistencia se registra igual; el mensaje queda en la bandeja |
| I-06 | Registrar cien entradas en un minuto | La cola absorbe el pico sin bloquear el colegio |
| I-07 | Apoderado sin sesión activa | El mensaje se conserva en el servidor y no se envía push |

## 6. Modo offline

| # | Escenario | Resultado esperado |
|---|---|---|
| O-01 | Abrir Mensajes sin conexión | Se ve el historial cacheado y el aviso de sin conexión |
| O-02 | Abrir Asistencias sin conexión | Pantalla de error; nunca datos inventados |
| O-03 | Recuperar la conexión | Sincronización incremental, sin duplicados |
| O-04 | Cerrar sesión y volver a entrar | La caché de mensajes sigue disponible |

## 7. Resiliencia multi-base

| # | Escenario | Resultado esperado |
|---|---|---|
| R-01 | Login con el teléfono ya en Redis y un colegio caído | 200; no se consulta el colegio |
| R-02 | Teléfono desconocido con todos los colegios caídos | 503 `UPSTREAM_SCHOOL_DB_UNAVAILABLE` |
| R-03 | Teléfono desconocido con los colegios sanos | 404, no 503 |
| R-04 | Un colegio falla repetidamente | El circuit breaker lo aísla y el resto sigue |
| R-05 | Cambiar el teléfono de contacto en el colegio | Tras la invalidación, el login usa el número nuevo |
| R-06 | Cambiar el teléfono sin invalidar la caché | El job nocturno lo corrige en la siguiente pasada |

## 8. Datos y ciclo de vida

| # | Escenario | Resultado esperado |
|---|---|---|
| D-01 | Mensaje con más de 24 meses | La purga lo elimina o lo anonimiza |
| D-02 | Eliminar la cuenta | Sesiones revocadas, push desactivado, datos anonimizados |
| D-03 | Eliminar la cuenta y revisar el colegio | El expediente del estudiante sigue intacto |
| D-04 | Apoderado con varios hijos | El selector cambia el contexto de toda la app |
| D-05 | Hijos en colegios distintos | Cada mensaje muestra el colegio correcto |

## 9. Normalización de teléfonos

Formatos reales que deben resolver al mismo número:

- `987654321`
- `+51 987 654 322`
- `51987654323`
- `(01) 987-654-324`

Entradas basura como texto vacío, letras o números de menos de nueve dígitos deben devolver
400 `VALIDATION_ERROR`.
