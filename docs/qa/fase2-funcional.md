# Fase 2 — Pruebas funcionales

Fecha: 2026-08-13. Deliverable: qué está cubierto automáticamente, qué exige un
dispositivo real, y qué no está cubierto por nada.

## Resultado de lo ejecutable en este entorno

| Suite | Comando | Resultado |
| --- | --- | --- |
| Backend | `python -m pytest -q` (desde `backend/`) | **149 / 149 pasan** en 6,7 s |
| App | `flutter test` (desde `frontend/mobile`) | **13 / 14 pasan**, 1 falla |
| Salud de producción | `GET /canal-api/health` | `status: ok`, `fcm_disponible: true` |

La única falla es la descrita en F1-01 (`formato_lima_test.dart`, fixture con fecha
fija). No hay ninguna otra regresión.

La suite del backend corre sobre SQLite en memoria, lo cual es una decisión
consciente y sólida: SQLite soporta índices únicos parciales, así que la garantía
de sesión única se prueba de verdad. Para validar contra PostgreSQL se ejecuta con
`TEST_USE_POSTGRES=1`.

---

## Matriz por área

### Autenticación — cobertura buena

| Caso | Cubierto por |
| --- | --- |
| Login correcto emite ambos tokens y crea sesión | `test_auth_login.py::test_login_correcto_emite_ambos_tokens_y_crea_la_sesion` |
| Documento que no coincide → 404 sin decir qué falló | `test_documento_que_no_coincide_devuelve_404`, `test_scaffold.py::test_student_link_not_found_no_revela_que_dato_fallo` |
| Teléfono desconocido → 404 (mismo código) | `test_telefono_desconocido_devuelve_404` |
| Teléfono con formato inválido → 400 | `test_telefono_invalido_devuelve_400` |
| Términos no aceptados o versión distinta → 400 | `test_login_sin_aceptar_terminos_devuelve_400`, `test_login_con_version_terminos_distinta_devuelve_400` |
| Segundo dispositivo → 409 y la sesión original intacta | `test_segundo_dispositivo_devuelve_409_y_la_sesion_original_sigue_intacta` |
| Mismo dispositivo reinstala → entra sin 409 | `test_el_mismo_dispositivo_vuelve_a_entrar_sin_409` |
| Dos logins concurrentes → gana uno solo | `test_dos_logins_concurrentes_solo_uno_gana`, `test_renovacion_carrera.py` |
| Curva de bloqueo 3 → 5 min → 10 min → 24 h | `test_superar_el_limite_de_intentos_devuelve_423`, `test_bloqueo_escala_a_diez_minutos_tras_desbloqueo`, `test_bloqueo_largo_tras_ocho_fallos_acumulados` |
| Los intentos no guardan datos personales | `test_los_intentos_no_guardan_datos_personales` |
| Redis caído no abre el login | `test_rate_limit_fail_closed.py` |
| Traspaso completo: solicitar, aprobar, entrar | `test_transferencia.py` (7 casos, incluye IDOR ajeno y límite por hora) |
| Login de administrador y sesión única de admin | `test_admin_login.py` (7 casos) |
| Tokens: tipo, firma ajena, ventana de rotación, jitter | `test_auth_tokens.py` (12 casos) |
| Reintento con refresh transparente en el cliente | `test/core/network/auth_interceptor_test.dart` (3 casos) |
| 409 → traspaso → reintento automático en el cliente | `test/features/auth/auth_cubit_test.dart` (5 casos) |

### Mensajes y aislamiento — cobertura buena en backend

| Caso | Cubierto por |
| --- | --- |
| La bandeja solo devuelve mensajes del apoderado | `test_mensajeria.py::test_listar_mensajes_solo_del_apoderado` |
| Marcar leído no toca mensajes ajenos | `test_marcar_leidos_no_toca_ajenos` |
| Idempotencia por `origen_evento` y apoderado | `test_idempotencia_origen_por_apoderado` |
| `emitido_en` sale siempre en UTC con `Z` | `test_emitido_iso_*` (3 casos) |
| El `estudiante_id` del cliente se contrasta con el directorio | `test_academico_authz.py` (3 casos) |
| Admin solo ve/afecta a su tenant | `test_administracion.py` (3 casos) |
| Confirmación de incidencia idempotente y 404 correcto | `test_confirmacion_incidencia.py` (5 casos) |

Nota relevante para F1-01: **el backend ya garantiza `emitido_en` en UTC con
sufijo `Z`** (`apps/mensajeria/services.py::_emitido_iso`, con tres pruebas). La
heurística equivalente del cliente es hoy código muerto salvo regresión del API, y
es justo la que tiene la prueba en rojo.

### Resiliencia multi-base — cobertura muy buena

`test_directorio.py` cubre 19 casos: aciertos y fallos de caché, un colegio caído
que no impide encontrar el vínculo en otro, circuito abierto y semiabierto con una
sola sonda, traducción a 503, reconciliación que da de baja lo que ya no existe,
precalentado, y que un vínculo inactivo no habilita login.

---

## Hueco 1 · La ingesta solo se prueba con `entrada`

**Severidad: alta.**

`test_ingesta.py` tiene un único caso (`test_crear_mensaje_desde_entrada`) y
`test_ingesta_http.py` usa siempre `tipo: "entrada"` en su cuerpo base. No hay
ninguna prueba para `salida`, `incidencia` ni `aviso`, aunque las cuatro plantillas
existen (`apps/mensajeria/plantillas/`) y el contrato las acepta:

```155:155:docs/estado-produccion.md
Ingesta acepta `entrada` \| `salida` \| `incidencia` \| `aviso`.
```

Esto importa porque el incidente de producción más reciente cayó exactamente ahí:
un `incidencia` con payload incompleto que reventaba al renderizar la plantilla y
devolvía `202` con `creados: 0`, sin que nada lo delatara. Y `aviso` es el tipo más
nuevo, el menos rodado y el que no tiene ni una prueba.

**Recomendación.** Un caso por tipo con payload completo, más un caso por tipo con
payload incompleto que verifique el código de error y que el evento no se marque
como procesado. Es la prueba que habría evitado el incidente.

## Hueco 2 · La app casi no tiene pruebas

**Severidad: alta.**

Todo `frontend/mobile/test/` son tres archivos: el interceptor, el formato de
fechas y el `AuthCubit`. No hay ni una prueba de:

- `MensajesCubit`: la caída a caché cuando falla la sincronización, el marcado
  optimista de leído, y que un fallo de red no vacíe la lista ya mostrada.
- `LocalDb`: la migración v5 → v6 (que borra la caché de mensajes), la cola de
  leídos pendientes y su reenvío.
- `MensajesRepository`: el cálculo de `since` con margen de seis horas y la
  paginación por cursor.
- Ninguna prueba de widget: ni login, ni bandeja, ni estados vacíos.

Con la lógica de sesión y caché que tiene esta app, publicar en Play sin cobertura
del camino de mensajes es el mayor riesgo de regresión silenciosa.

**Recomendación.** Antes del primer rollout, tres pruebas de cubit (mensajes en
línea, mensajes offline, marcado de leído con red caída) y una de `LocalDb` sobre
`sqflite_common_ffi`. Las de widget pueden esperar.

## Hueco 3 · La pestaña Notas no hace nada

**Severidad: media (riesgo de revisión en Play).**

`NotasPage` consulta `/feature-flags` y, en los dos caminos posibles, muestra un
estado vacío: «Próximamente» si el flag está apagado, «El módulo de notas estará
disponible aquí» si está encendido. Es decir, encender el flag no cambia nada
funcional.

Una pestaña permanente de la navegación principal que nunca muestra contenido entra
en el terreno de «funcionalidad incompleta» que el revisor de Play puede marcar.

**Recomendación.** Ocultar la pestaña mientras el flag esté apagado, en lugar de
mostrarla vacía. El texto «se activarán sin una nueva versión» pierde sentido si la
pestaña no existe hasta que haya notas, y así no se compromete la revisión.

## Hueco 4 · Foto del estudiante en el aviso

**Severidad: baja (verificar contra el SRS).**

No hay ninguna referencia a foto o imagen en el pipeline de mensajería: ni en las
plantillas, ni en `metadata`, ni en el payload de push. Si el SRS v5 la exige en el
aviso de entrada, es un hueco de producto; si era una idea descartada, conviene
anotarlo para que no se reabra.

## Hueco 5 · Comportamiento del proxy ante errores no-JSON

**Severidad: media. Pendiente de tu autorización.**

Para cerrar F1-06 hace falta comprobar contra producción qué devuelve el borde ante
un 401/403/404: si es JSON del canal o HTML del SIE. La comprobación es de solo
lectura y sin credenciales (`GET /v0.1/mensajes` sin token, más una ruta
inexistente), pero toca producción, así que queda a la espera de tu OK, igual que
la Fase 4.

---

## Checklist manual en dispositivo (no automatizable aquí)

Requiere dos teléfonos y una cuenta de prueba del colegio.

1. **Doble sesión.** Entrar en el teléfono A. Entrar en B con la misma credencial:
   debe salir 409 con la pantalla de sesión denegada, A debe recibir el aviso push
   de intento de acceso, y la sesión de A debe seguir viva.
2. **Traspaso.** Desde B pedir el traspaso; aprobar en A. A debe volver al login y
   B entrar sin pedir nada más. Repetir rechazando: A sigue dentro.
3. **Bloqueo.** Tres intentos con documento incorrecto: mensaje de bloqueo con los
   minutos correctos. Comprobar que el texto no dice «5 intentos».
4. **Términos.** Primer login sin marcar la aceptación: debe rechazarse.
5. **Offline.** Con la app abierta, activar modo avión: la bandeja debe seguir
   mostrando lo cacheado y marcar el estado offline. Asistencias e incidencias
   deben avisar de que necesitan conexión, no quedarse en blanco.
6. **Leídos sin red.** Abrir un mensaje en modo avión, restaurar red y refrescar:
   el leído debe haber subido (cola `leidos_pendientes`).
7. **Multi-hijo y multi-colegio.** Cambiar de hijo y comprobar que asistencias,
   incidencias y la bandeja cambian de forma consistente.
8. **Push en frío.** App cerrada, generar una entrada: la notificación debe llegar
   y abrir la bandeja en el mensaje correcto (probar en MIUI, que es el caso malo).
9. **Eliminar cuenta.** Confirmar con el documento, verificar que se cierra sesión
   y que un login posterior se comporta como cuenta nueva.
10. **Tras rotar el secreto del servidor.** Sesión antigua: la app debe llevar al
    login con un mensaje claro, no a un estado de «sin conexión».
