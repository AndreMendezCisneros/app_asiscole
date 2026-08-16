# Fase 3 — UX e intuitividad

Fecha: 2026-08-13. Revisión estática de las pantallas clave (login, bandeja, shell,
perfil, estados vacíos y copy de errores). Propuestas priorizadas, **sin
implementar**.

El público es apoderados de colegio en Perú, muchos con teléfonos de gama media y
poca tolerancia a la fricción: el criterio que uso es que ninguna pantalla deje al
usuario sin saber qué hacer a continuación.

## Lo que ya funciona bien

La app no parte de cero en calidad: hay identidad de marca coherente (morado
`#5B21E6`, logo presente en login, estados vacíos y perfil), tipos de mensaje con
color e icono propios (entrada verde, salida índigo, incidencia ámbar, aviso
morado), marca de tiempo relativa (hora si es hoy, día y mes si es anterior),
búsqueda con debounce de 220 ms, filtros por leído/hijo/colegio que solo aparecen
cuando hacen falta (dos o más hijos, dos o más colegios), pull-to-refresh, tour de
primera vez por sección y refresco automático al volver a la app. El login explica
de dónde salen los datos y aclara que el canal es de solo lectura. Es un nivel
bastante por encima del típico primer release.

Lo que sigue son huecos concretos, ordenados por lo que yo arreglaría primero.

---

## Prioridad 1 — impacto alto, esfuerzo bajo

### U-01 · El botón «Ingresar» está muerto hasta marcar la casilla

**Evidencia.** `login_page.dart:330` deshabilita el botón si `!_aceptaTerminos`, y
`_enviar()` contiene un aviso para ese caso que nunca se puede ver:

```40:47:frontend/mobile/lib/features/auth/presentation/login_page.dart
    if (!_aceptaTerminos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar los términos y la política de privacidad.'),
        ),
      );
      return;
    }
```

El apoderado llena teléfono y documento, pulsa el botón y **no pasa nada**, sin
mensaje ni pista de qué falta. Es el peor callejón sin salida posible: está en la
primera pantalla y bloquea el 100% del uso.

**Propuesta.** Dejar el botón siempre habilitado y que `_enviar()` muestre el aviso
que ya existe (o resalte la casilla). El código del aviso ya está escrito.

### U-02 · Tocar una pestaña deshabilitada en modo offline no dice nada

**Evidencia.** `shell_page.dart:126-130`: en `OfflineMessagesOnly` las pestañas
Asistencias, Incidencias, Notas y Perfil quedan en gris y su `onTap` retorna sin
hacer nada. Hay una barra ámbar arriba, pero el usuario que toca «Asistencias» tres
veces sin respuesta concluye que la app está trabada, no que necesita conexión.

**Propuesta.** Al tocar una pestaña deshabilitada, mostrar un aviso puntual:
«Necesitas conexión para ver asistencias». Es una línea y elimina la sensación de
app colgada.

### U-03 · El detalle del mensaje se contradice con la lista

**Evidencia.** `mensajes_page.dart:384-391`: `_detalle(m)` lanza
`MensajesCubit.abrir(m)` (que marca leído de forma optimista y emite una copia
nueva) y en paralelo abre el sheet con la instancia **antigua**. Resultado: la lista
detrás ya muestra el mensaje como «Leído» y el sheet abierto encima dice «Estado:
pendiente de lectura».

**Propuesta.** Pasar al sheet el mensaje con `leido: true`, o simplemente no mostrar
el estado de lectura en el detalle: al apoderado no le aporta nada saber si el
sistema registró su propia lectura.

### U-04 · Eliminar la cuenta no advierte de nada

**Evidencia.** `perfil_page.dart:490-537`: el diálogo pide el documento del
estudiante y ofrece «Cancelar» / «Eliminar». No dice que la acción es
irreversible, ni qué se borra, ni que se dejarán de recibir avisos, ni que hay que
volver a registrarse para recuperarlos.

Además la caché local de mensajes sobrevive a la eliminación (ver F1-05), lo que es
un problema de cumplimiento, no solo de UX.

**Propuesta.** Texto explícito de consecuencias antes de pedir el documento, y
borrado de la caché local como parte de la operación.

### U-05 · Cuando el login falla, no hay a quién acudir

**Evidencia.** `login_page.dart:335-342` explica bien el problema («estos datos los
registra el colegio… comunícate con la institución») pero no ofrece ninguna acción:
no hay teléfono, WhatsApp ni correo de soporte.

El login puede fallar por un dato desactualizado en el sistema del colegio, algo que
el apoderado no puede resolver solo. Si además cae en el bloqueo de tres intentos,
se queda esperando sin saber a quién escribir.

**Propuesta.** Un enlace de soporte accionable en el panel de ayuda. Antes del login
la app no sabe de qué colegio es el usuario, así que lo razonable es un contacto
único de soporte Asiscole que derive al colegio.

## Prioridad 2 — impacto medio

### U-06 · El modo oscuro está declarado pero no implementado

**Evidencia.** `app.dart:107-108` registra `theme` y `darkTheme`, y
`AppTheme._construir` sí contempla `Brightness.dark`. Pero todas las pantallas fijan
colores claros a mano (`backgroundColor: AppTheme.fondo`, tarjetas `AppTheme.blanco`,
texto `AppTheme.texto`).

En un teléfono con modo oscuro activo —muy común— las páginas se ven claras
mientras los diálogos, los bottom sheets y los snackbars, que sí siguen el
`ColorScheme`, se ven oscuros. El detalle de mensaje queda como una hoja oscura con
una burbuja blanca dentro.

**Propuesta.** Decidir una de las dos: fijar `themeMode: ThemeMode.light` y quitar
`darkTheme` (media hora, coherente con el diseño actual), o completar el soporte
oscuro (varios días). Para la versión 1 recomiendo lo primero.

### U-07 · Dos avisos de «sin conexión» a la vez

**Evidencia.** La barra ámbar del shell (`shell_page.dart:78-110`) aparece con
`OfflineMessagesOnly`, y la bandeja añade su propia línea ámbar
(`mensajes_page.dart:218-237`) cuando la sincronización falla. Los dos casos suelen
coincidir, así que el usuario ve dos veces casi el mismo mensaje, uno debajo del
otro, comiéndose el espacio útil de una pantalla pequeña.

**Propuesta.** Un único indicador. El del shell es el mejor sitio: es persistente y
no se pierde al hacer scroll.

### U-08 · Las etiquetas de la barra inferior van a 10 px

**Evidencia.** `shell_page.dart:204`: `fontSize: 10` con cinco destinos. El área
táctil sí cumple (unos 54 px de alto), pero 10 px queda por debajo del mínimo
recomendado de 12 sp y este público incluye a muchos usuarios con presbicia.

**Propuesta.** Subir a 11-12 px, y si no caben las cinco etiquetas, acortar
«Asistencias» a «Asistencia» o mostrar la etiqueta solo en la pestaña activa.

### U-09 · Filtro sin resultados y sin salida

**Evidencia.** `mensajes_page.dart:317-321`: cuando los filtros dejan la lista
vacía se muestra «No hay mensajes con ese filtro» sin ninguna acción.

**Propuesta.** Añadir «Quitar filtros» en ese estado vacío. Reutiliza el
`onReintentar` que `EmptyStateAsiscole` ya soporta.

## Prioridad 3 — pulido

### U-10 · La búsqueda es local y no lo dice

`_filtrar` opera sobre lo que hay en memoria (lo descargado y cacheado). Buscar el
aviso de hace ocho meses no devuelve nada y parece un fallo. Bastaría un texto en el
estado vacío: «Solo se buscan los mensajes descargados».

### U-11 · El detalle es una lista de pares clave-valor

`_DetalleMensajeSheet` renderiza «Hijo: …», «Colegio: …», «Grado: 3», «Sección: A»,
«Hora del evento: …» como líneas de texto plano del mismo tamaño y color. Funciona,
pero el dato importante (el texto del mensaje) compite con cinco metadatos. Agrupar
grado y sección en una sola línea y darle jerarquía visual al mensaje mejoraría la
lectura de un vistazo.

### U-12 · El campo de documento fuerza mayúsculas

`login_page.dart:261` aplica `TextCapitalization.characters` con teclado de texto,
cuando el `codigo_barras` habitual es numérico (`70123456`). No rompe nada, pero al
apoderado le aparece un teclado de letras en mayúscula para escribir números.

---

## Resumen de prioridades

| Id | Hallazgo | Impacto | Esfuerzo |
| --- | --- | --- | --- |
| U-01 | Botón «Ingresar» sin respuesta ni explicación | Alto | Muy bajo |
| U-02 | Pestaña deshabilitada muda en offline | Alto | Muy bajo |
| U-03 | Detalle dice «pendiente» y la lista «leído» | Medio | Muy bajo |
| U-04 | Eliminar cuenta sin advertencia ni borrado local | Alto | Bajo |
| U-05 | Sin contacto de soporte cuando el login falla | Alto | Bajo |
| U-06 | Modo oscuro a medias | Medio | Bajo (light-only) |
| U-07 | Dos banners de offline simultáneos | Medio | Muy bajo |
| U-08 | Etiquetas de navegación a 10 px | Medio | Muy bajo |
| U-09 | Estado vacío de filtros sin acción | Medio | Muy bajo |
| U-10 | Búsqueda local sin explicar | Bajo | Muy bajo |
| U-11 | Jerarquía del detalle de mensaje | Bajo | Bajo |
| U-12 | Teclado en mayúsculas para un dato numérico | Bajo | Muy bajo |

Nueve de los doce son cambios de menos de veinte líneas. U-01, U-02, U-04 y U-05
son los que yo haría antes de publicar; el resto puede ir en la primera
actualización.
