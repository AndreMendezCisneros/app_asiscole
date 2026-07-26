# Privacidad, retención y publicación en tiendas

Requisitos que condicionan la publicación de la app y el tratamiento de datos de menores.
Base legal: Ley N.º 29733 de Protección de Datos Personales del Perú.

---

## 1. Qué datos trata el sistema

| Dato | Origen | Dónde vive | Para qué |
|---|---|---|---|
| Teléfono del apoderado | `estudiantes.telefono_contacto` | Directorio central, normalizado a E.164 | Identificar al apoderado en el login |
| Documento del estudiante | `estudiantes.codigo_barras` | Solo en tránsito durante el login | Verificar el vínculo |
| Nombre, grado y sección | Base del colegio | Se cachea en el directorio | Mostrar el estudiante activo |
| Entradas y salidas | `registros_llegada` | Se leen en línea; el aviso queda como mensaje | Informar al apoderado |
| Incidencias | `incidencias` | Igual que arriba | Informar al apoderado |
| Mensajes | Los genera el backend | Base central y caché del dispositivo | Bandeja del apoderado |
| Token de push | Dispositivo | Base central | Entregar notificaciones |

El documento del estudiante nunca se almacena en la base central del canal. Para el control
de intentos de login se guarda solo un hash SHA-256 de la combinación teléfono más documento.

## 2. Principios aplicados

**Finalidad.** Los datos se usan únicamente para notificar al apoderado sobre su hijo. No hay
perfilado, publicidad ni cesión a terceros.

**Minimización.** El dispositivo cachea solo los mensajes ya recibidos. Los listados de
asistencia e incidencias se consultan en línea y no se replican localmente.

**Seguridad.** TLS 1.2 o superior, tokens en Keychain o Keystore, aislamiento por API con
tests de autorización negativa obligatorios, y prohibición de volcar datos personales a los
logs.

## 3. Retención

Los mensajes de la base central se purgan o anonimizan a los **24 meses** de su emisión.
La columna `asis_mensaje.retenido_hasta` materializa esa fecha y un job diario de Celery
ejecuta la purga.

La caché del dispositivo la controla el apoderado: se conserva hasta que él la borre, incluso
si la cuenta queda suspendida. Cerrar sesión elimina los tokens, no el historial.

## 4. Derechos del titular (ARCO)

| Derecho | Cómo se ejerce |
|---|---|
| Acceso | El apoderado ve en la app todos los mensajes que le conciernen |
| Rectificación | A través del colegio, que corrige el dato en su sistema; el directorio se reconcilia |
| Cancelación | Eliminación de cuenta desde Perfil (RF-I06) |
| Oposición | Cierre de sesión y eliminación de cuenta, con canal de soporte del colegio |

La eliminación de cuenta revoca sesiones, desactiva el push y anonimiza los datos del
apoderado. El expediente académico del estudiante pertenece al colegio y no se borra por esta
vía: es un dato del centro educativo, no del canal.

Queda por confirmar con el área legal del colegio si el tratamiento de datos de menores exige
comunicación ante la Autoridad Nacional de Protección de Datos Personales.

## 5. Consentimiento

El apoderado acepta la política de privacidad y los términos en el primer registro. El texto
debe explicar en lenguaje llano qué datos se usan, para qué y cuánto tiempo se conservan.

## 6. Checklist de publicación

### Google Play

- [ ] URL pública de la política de privacidad
- [ ] Formulario de Data Safety declarando teléfono, mensajes e identificadores de dispositivo
- [ ] Declarar que la app va dirigida a adultos (apoderados), no a menores
- [ ] API target reciente y cuenta de organización
- [ ] Explicar en las notas de revisión que las credenciales las entrega el colegio

### Apple App Store

- [ ] Privacy Nutrition Labels coherentes con el tratamiento real
- [ ] Flujo de eliminación de cuenta visible dentro de la app (requisito obligatorio)
- [ ] Descripción clara del mecanismo de login, que es inusual y puede levantar dudas
- [ ] Cuenta de demostración para el equipo de revisión

### Ambas

- [ ] Capturas, ícono y clasificación por edad
- [ ] Contacto de soporte del colegio
- [ ] Texto de privacidad en español

## 7. Riesgo aceptado en la versión 1

El login con teléfono y documento del estudiante, sin OTP, permite que un tercero que conozca
ambos datos intente entrar. Se mitiga con coincidencia estricta, límite de intentos, bloqueo
temporal, sesión única y aviso al dispositivo activo. Está documentado en el ADR-07 y se
revisará cuando el colegio pueda costear el servicio de mensajería.
