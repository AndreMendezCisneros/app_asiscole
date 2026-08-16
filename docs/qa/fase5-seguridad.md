# Fase 5 — Seguridad y privacidad de datos de menores

Fecha: 2026-08-13. Base legal: Ley N.º 29733 y la regla interna
[`datos-menores`](../../.cursor/rules/datos-menores.mdc). Se cruza con
[`privacidad-y-tiendas.md`](../privacidad-y-tiendas.md).

El veredicto corto: el diseño de privacidad de este canal es mejor que el de la
mayoría de apps escolares que uno ve. Los tres hallazgos que siguen son huecos
concretos en la implementación, no fallos de criterio.

---

## S-01 · El APK se firma con la clave de depuración, y eso es un agujero real

**Severidad: alta.**

Ya salió en F1-02 como bloqueo para Play, pero tiene una dimensión de seguridad
propia que merece su propio hallazgo, porque la distribución **hoy es por sideload**:

```62:66:frontend/mobile/android/app/build.gradle.kts
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
```

Sin `key.properties`, el APK va firmado con el keystore de depuración de Android,
cuya clave privada es **la misma en todas las instalaciones del SDK y es pública**.
Consecuencia: cualquiera puede compilar una aplicación con el mismo
`applicationId` (`pe.asiscole.asiscole_app`), firmarla con esa misma clave de debug
y el teléfono la aceptará como una **actualización** de la app legítima, heredando
sus datos. En un modelo de reparto por WhatsApp o por enlace del colegio, donde el
apoderado ya está acostumbrado a instalar de fuentes externas, es un vector
verosímil.

**Recomendación.** Generar el keystore de release, custodiarlo fuera del repo (ya
está cubierto por `.gitignore`: `*.keystore`, `*.jks`) y firmar con él **antes de
repartir el próximo APK**, incluso si la publicación en Play se retrasa.

## S-02 · La copia de seguridad de Android está habilitada por omisión

**Severidad: media-alta.**

El manifest no declara `android:allowBackup` ni reglas de extracción de datos, y en
todo el proyecto no existe ninguna referencia a `allowBackup`,
`dataExtractionRules` ni `fullBackupContent`. El valor por omisión de Android es
`true`.

Eso significa que `asiscole.db` —que guarda el texto de los mensajes y el nombre
del estudiante en claro— entra en la copia automática de Google Drive del usuario y
puede extraerse con `adb backup` en los dispositivos que lo permiten. Es
exactamente el dato que la regla de minimización quiere mantener acotado al
dispositivo.

**Recomendación.** `android:allowBackup="false"` en el manifest de release, o unas
reglas de extracción que excluyan la base local y el almacén cifrado. Además afecta
al formulario de Data Safety de Play: hoy habría que declarar que los datos se
respaldan en la nube del usuario.

## S-03 · Eliminar la cuenta deja los mensajes del menor en la base

**Severidad: media.**

`eliminar_cuenta` hace bien lo suyo: revoca sesiones, desactiva push, inactiva el
directorio y anonimiza al apoderado (`telefono = deleted:<uuid>`, alias a nulo,
estado eliminado, auditoría). Pero **no toca `asis_mensaje`**, y esas filas
contienen el nombre del estudiante tanto en `texto` como en
`metadata.estudiante_nombre`. Se quedan ahí hasta que la purga de retención las
alcance:

```132:137:backend/apps/mensajeria/tasks.py
def purgar_mensajes_vencidos() -> dict[str, int]:
    """Anonimiza mensajes que superaron MESSAGE_RETENTION_MONTHS (RNF-11)."""
    ahora = timezone.now()
    qs = Mensaje.objects.filter(retenido_hasta__lte=ahora).exclude(texto="[eliminado]")
```

Es decir, hasta 24 meses después de emitidos. Y en el dispositivo la caché local
tampoco se borra (F1-05). El resultado es que el ejercicio del derecho de
cancelación deja rastro de datos de un menor en dos sitios.

Se puede defender que los mensajes son historial del colegio y no del apoderado,
igual que el expediente académico. Pero el texto del mensaje lo genera el canal, no
el colegio, y `privacidad-y-tiendas.md` §4 promete que la eliminación «anonimiza los
datos del apoderado» sin aclarar esta excepción.

**Recomendación.** Decidirlo explícitamente y que el código y el documento digan lo
mismo. Lo más limpio es aplicar la misma anonimización de la purga a los mensajes
del apoderado eliminado, y borrar la caché local en la misma operación.

## S-04 · Las claves de Firebase del cliente están a un `commit -a` de entrar al repo

**Severidad: media (proceso).**

El propio `.gitignore` deja escrita la política:

```28:33:.gitignore
# Firebase cliente: no versionar claves reales; usar *.example y canal privado
google-services.json
GoogleService-Info.plist
# firebase_options.dart SÍ puede ir al repo solo como stub sin claves reales
# (las reales viven en secrets/ en la máquina local).
# No commitear firebase_options.dart si contiene claves reales; dejar el stub.
```

Y ahora mismo `frontend/mobile/lib/firebase_options.dart` está modificado con las
claves reales del proyecto `asiscole-canal`. La regla depende de que nadie escriba
`git commit -a`. Un comentario no es un control.

**Recomendación.** Sacar el archivo del control de versiones (ignorarlo de verdad) y
dejar solo el `.example`, que es lo que la propia nota pide.

## S-05 · Riesgos aceptados que conviene reconfirmar

- **Login sin OTP.** Documentado en ADR-07 y en `privacidad-y-tiendas.md` §7. Quien
  conozca teléfono y documento del estudiante puede entrar. Se mitiga con
  coincidencia exacta, bloqueo escalonado, sesión única y aviso push al dispositivo
  activo. Sigue siendo el riesgo principal del producto y hay que decirlo así en la
  revisión de Play si preguntan por el método de autenticación.
- **Capturas de pantalla.** No se usa `FLAG_SECURE`, así que la bandeja con nombres
  de estudiantes se puede capturar y aparece en el conmutador de apps recientes. Es
  razonable no bloquearlo (el apoderado querrá guardar un aviso), pero es una
  decisión que debería estar escrita, no implícita.
- **HSTS con subdominios.** `SECURE_HSTS_INCLUDE_SUBDOMAINS = True` y un año de
  duración. Correcto para `jeanpiaget.asiscole.com`, pero si algún subdominio del
  colegio se sirviera sin HTTPS quedaría inaccesible durante un año en los
  navegadores que ya vieron la cabecera. Vale la pena confirmarlo con quien opera el
  DNS.

---

## Lo que está bien resuelto

Esto no es relleno: son los controles que hacen que los hallazgos de arriba sean
puntuales y no sistémicos.

**El push no lleva ni un dato personal.** Es la decisión de privacidad más
importante y está bien ejecutada. El payload solo lleva `tipo`, `message_id` y
`destino`, y el cuerpo visible es genérico («Hay un nuevo aviso de ingreso»). El
nombre del estudiante, la falta y la hora no atraviesan FCM. La app resuelve el
contenido después, con el `data_token` del apoderado.

**Los logs no pueden filtrar datos personales por accidente.** El formatter JSON
redacta cualquier campo `extra` cuyo nombre contenga `telefono`, `codigo_barras`,
`dni`, `nombre`, `mensaje`, `token`, `authorization` y una docena más, incluso
dentro de diccionarios anidados. `django.db.backends` está fijado en `WARNING` para
que no salgan consultas SQL con datos, y de las excepciones solo se emite el tipo y
el traceback, no el texto. Hay tres pruebas que lo verifican.

**Las credenciales de login nunca se guardan.** Ni el teléfono ni el
`codigo_barras` llegan a la base: `asis_intento_login` guarda un SHA-256 de la
combinación, y la IP —también dato personal— se hashea antes de convertirse en
clave de caché.

**El rate-limit falla cerrado.** Si Redis no responde, `_asegurar_cache_auth`
devuelve 429 en vez de dejar el login sin barrera. Con `IGNORE_EXCEPTIONS = True` en
la caché, eso no era gratis: hay una sonda explícita y una prueba dedicada.

**Los dos tokens están de verdad separados.** `decodificar` exige que el claim `typ`
coincida, así que un `session_token` no abre un endpoint de negocio y un
`data_token` no renueva la sesión. El `jti` del token de sesión es el de la fila de
`asis_sesion_activa`, de modo que revocar la sesión invalida el token sin necesidad
de lista negra. Cuatro pruebas cubren la confusión de tipos y la firma ajena.

**La API deniega por omisión.** `DEFAULT_PERMISSION_CLASSES` es
`DenegarPorDefecto`: una vista nueva sin permiso explícito no queda abierta.

**RLS en la central.** `007_central_rls_lockdown.sql` activa RLS sin políticas en
las once tablas `asis_*` y revoca privilegios a `anon` y `authenticated`, de modo
que PostgREST de Supabase no puede leer nada del canal aunque alguien conozca la
URL. Django entra con rol de servicio que hace bypass. El script es idempotente.

**El aislamiento vive en la API, no en la interfaz.** El `estudiante_id` que manda
el cliente siempre se contrasta contra `asis_directorio` antes de consultar el
colegio, y hay pruebas de autorización negativa (un apoderado con el id de otro
estudiante, un admin de otro tenant).

**La clave de ingesta se compara en tiempo constante** (`hmac.compare_digest`) y si
no está configurada el endpoint responde 401 a todo, en vez de quedar abierto.

**Transporte.** HTTPS con Caddy, `usesCleartextTraffic` solo en el manifest de
depuración, HSTS de un año, `nosniff` y `X-Frame-Options: DENY`. El release solo
pide tres permisos: `INTERNET`, `ACCESS_NETWORK_STATE` y `POST_NOTIFICATIONS`.

**Retención.** `asis_mensaje.retenido_hasta` materializa los 24 meses y un job
diario de Celery anonimiza lo vencido. Existe de verdad y está planificado en
`CELERY_BEAT_SCHEDULE`.
