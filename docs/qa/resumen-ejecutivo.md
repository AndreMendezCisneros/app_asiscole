# Auditoría QA pre-lanzamiento — Resumen ejecutivo

Fecha: 2026-08-13 · Ámbito: Asiscole Messenger `1.0.0+1` (Flutter) + canal Django en
producción (`jeanpiaget.asiscole.com/canal-api/v0.1`), dos colegios activos.

Informes por fase: [estática](fase1-estatica.md) ·
[funcional](fase2-funcional.md) · [UX](fase3-ux.md) ·
[rendimiento](fase4-rendimiento.md) · [seguridad](fase5-seguridad.md) ·
[Google Play](fase6-google-play.md) · [versiones (diseño)](fase7-versiones.md)

## Veredicto: no listo para publicar en Play todavía. Faltan unos días, no semanas.

Y conviene separar las dos cosas, porque no están igual de maduras:

**El producto está listo.** El canal funciona en producción con dos colegios, la
arquitectura de privacidad es sólida (el push no lleva ni un dato personal, los logs
redactan datos personales de forma automática, las credenciales de login nunca se
guardan en claro), el aislamiento entre apoderados se aplica en la API y no en la
interfaz, y las 149 pruebas del backend pasan.

**La infraestructura de publicación no existe.** Lo que bloquea no es el producto:
es que nunca se ha preparado un release de verdad. No hay keystore, no hay AAB, no
hay reporte de crashes y no hay control de versiones. Son cuatro huecos conocidos, sin
sorpresas y con solución conocida.

## (a) Críticos que bloquean Play

| # | Hallazgo | Trabajo |
| --- | --- | --- |
| 1 | **Sin firma de release.** El APK va firmado con la clave de depuración, que es pública. Play lo rechaza. ([F1-02](fase1-estatica.md), [S-01](fase5-seguridad.md)) | Horas |
| 2 | **Sin AAB.** Solo existe la ruta de build de APK; Play exige App Bundle. ([Fase 6](fase6-google-play.md)) | Horas |
| 3 | **Sin Crashlytics** en una app ofuscada: el rollout escalonado sería a ciegas. ([F1-03](fase1-estatica.md), [Fase 7](fase7-versiones.md)) | 1 día |
| 4 | **`flutter test` en rojo** (1 de 14). La causa es un fixture con fecha fija, no el código, pero el parseo de horas sí depende del reloj y merece limpiarse. ([F1-01](fase1-estatica.md)) | Horas |

El punto 1 es el más urgente de todos, y no por Play: el reparto por sideload **ya
está en marcha**, y cualquiera puede firmar una app con el mismo identificador usando
esa misma clave pública y hacerla pasar por una actualización de la legítima.

Además, dos que yo arreglaría antes de subir aunque no sean bloqueos formales:
`android:allowBackup` está en `true` por omisión, así que la base local con los
mensajes y el nombre del estudiante entra en la copia de Google Drive
([S-02](fase5-seguridad.md)); y la pestaña «Notas» está permanentemente vacía, lo que
un revisor puede leer como app incompleta ([Hueco 3](fase2-funcional.md)).

Y un trámite que suele costar un rechazo: el login no es autoservicio, así que hay
que dar **credenciales de un estudiante de prueba** en las notas de revisión, más la
URL web de eliminación de cuenta que Play exige aparte del botón dentro de la app.

## (b) Aceptable después del lanzamiento

- **Privacidad:** eliminar la cuenta anonimiza al apoderado pero deja los mensajes
  con el nombre del menor hasta la purga de 24 meses, y no borra la caché del
  dispositivo. Conviene decidirlo pronto y que el código y la política digan lo mismo
  ([S-03](fase5-seguridad.md), [F1-05](fase1-estatica.md)).
- **UX, cinco puntos de prioridad 1** ([Fase 3](fase3-ux.md)): botón de login
  deshabilitado sin explicar por qué, pestañas inertes al tocarlas sin red, el estado
  de leído incoherente entre lista y detalle, la eliminación de cuenta sin aviso de
  irreversibilidad y la falta de un contacto de soporte cuando el login falla. Ninguno
  rompe nada; todos generan llamadas al colegio.
- **Cobertura de pruebas:** la ingesta solo se prueba con `entrada`, y `salida`,
  `incidencia` y `aviso` van sin red de seguridad, justo lo que se rompió hace poco en
  `asis_academy`. La app apenas tiene pruebas ([Fase 2](fase2-funcional.md)).
- **Rendimiento:** no se ejecutó carga (k6 no está instalado y el VPS es compartido).
  Los scripts existentes asumen un host bastante mayor que el real de 4 vCPU / 8 GB,
  así que sus umbrales no son creíbles hoy. Sin medir quedan el pico de ingesta y el
  pico de login del primer día, que es el más caro. Mitigación práctica: rollout al
  5-10 % ([Fase 4](fase4-rendimiento.md)).
- **Robustez del cliente:** un 403 o 404 sin cuerpo JSON hace que la app anuncie
  «cuenta suspendida» ([F1-06](fase1-estatica.md)); los timeouts de 20-30 s son largos
  de más para móvil ([T-01](fase4-rendimiento.md)).
- **Operación:** `firebase_options.dart` con claves reales está a un `commit -a` de
  entrar al repositorio, contra lo que el propio `.gitignore` pide
  ([S-04](fase5-seguridad.md)).

## (c) Riesgos asumidos, a reconfirmar por escrito

- **Login sin OTP** (ADR-07): quien conozca el teléfono y el documento del estudiante
  entra. Mitigado con coincidencia exacta, bloqueo escalonado tras 3 fallos, sesión
  única y aviso al dispositivo activo. Es el riesgo principal del producto y hay que
  poder explicarlo si Play pregunta.
- **La IP de origen** se toma del último salto de `X-Forwarded-For`. Es lo correcto
  con Caddy como único proxy, pero poner Cloudflare delante rompería el rate-limit sin
  ningún aviso ([F1-10](fase1-estatica.md)).
- **Sin `FLAG_SECURE`:** la bandeja con nombres de estudiantes se puede capturar.
  Razonable, pero debería estar escrito como decisión.

## Camino más corto a producción

1. Keystore de release y `flutter build appbundle`, más `allowBackup="false"` y
   ocultar la pestaña Notas.
2. Arreglar la prueba en rojo y el parseo de horas.
3. Crashlytics con símbolos, cuidando de no enviar datos personales.
4. Internal testing → closed testing con apoderados de Jean Piaget → producción al
   5-10 % vigilando vitals.
5. En paralelo: la URL web de eliminación de cuenta, el Data Safety y los cinco
   arreglos de UX de prioridad 1.
6. Después de la primera publicación: endpoint de versión mínima e `in_app_update`
   ([Fase 7](fase7-versiones.md)).

Nada de esto es código de producto todavía: la auditoría fue en modo informe. Dime
qué apruebo implementar y en qué orden.
