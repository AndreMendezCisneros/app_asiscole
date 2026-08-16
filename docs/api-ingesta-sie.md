# API de ingesta — SIE Asiscole → canal apoderado

Para que el sistema web (Jean Piaget, Academy u otro colegio) avise al backend
del canal cuando registra una **entrada**, **salida**, **incidencia**, **aviso**
(pensión o cita) o **nota semanal**.

Contrato canónico: [`openapi.yaml`](openapi.yaml) → `POST /v0.1/ingesta/eventos`.

---

## Endpoint

```
POST {BASE_URL}/v0.1/ingesta/eventos
```

Ejemplos de `BASE_URL`:

| Entorno | Base |
|---------|------|
| Local PC | `http://192.168.18.206:8000` (o la IP de tu máquina) |
| Emulador Android → PC | `http://10.0.2.2:8000` |
| Producción | `https://api.tudominio.com` |

### Cabeceras

| Cabecera | Valor |
|----------|--------|
| `Content-Type` | `application/json` |
| `X-Asiscole-Ingest-Key` | El valor de `INGEST_API_KEY` del `.env` del canal |

No usa JWT de apoderado. Solo la API key de ingesta.

### Cuerpo (JSON)

| Campo | Tipo | Obligatorio | Notas |
|-------|------|-------------|--------|
| `tenant_id` | string | sí | Debe coincidir con `.env` → `SCHOOL_DATABASES[].tenant_id` (ej. `jean_piaget`) |
| `tipo` | string | sí | `entrada` \| `salida` \| `incidencia` \| `aviso` \| `nota` |
| `id_estudiante` | int | sí | PK en la BD del colegio (`estudiantes.id`) |
| `id_registro` | int | sí | PK de origen (idempotencia). Cita: `citas_padres.id_cita`. Nota: `notas_semana.id`. |
| `payload` | object | sí | Datos para la plantilla del mensaje |

**No enviar** `telefono_contacto` ni `codigo_barras` en el payload (privacidad Ley 29733). El canal resuelve destinatarios con `asis_directorio`.

### Respuesta `202 Accepted`

```json
{
  "creados": 1,
  "origen_evento": "entrada:1042",
  "apoderados_notificados": 1
}
```

- `creados: 0` → el evento se aceptó pero **no hay apoderado vinculado** (tipos de bandeja) o la nota ya existía (reintento).
- Mismo `(tipo, id_registro)` otra vez → no duplica mensajes ni filas de nota.

---

## Destinos (no mezclarlos)

| Qué sale del SIE | `tipo` | Dónde en la app |
|------------------|--------|-----------------|
| Pensión | `aviso` + `payload.contexto: pension` | Bandeja de avisos |
| Cita (al crear, no al reprogramar) | `aviso` + `payload.contexto: cita` | Bandeja de avisos |
| Llegada / salida | `entrada` / `salida` | Sección Asistencias (live BD colegio) + bandeja |
| Nota semanal | `nota` | Sección Notas (`asis_nota`) |
| Incidencia | `incidencia` | Incidencias (live) + bandeja |

Si el canal trata la nota como aviso, solo llena la bandeja y no hay historial.
Si trata la cita como registro de sección, no llega al padre como mensaje.

Compatibilidad: un `tipo: aviso` con `payload.contexto: nota` (SIE Academy
anterior a agosto 2026) se guarda en `asis_nota`, no en la bandeja. Los alias
`semana` → `semana_codigo` y `area` → `area_nombre` también se aceptan.
El contrato nuevo sigue siendo `tipo: nota`.

El `id_estudiante` es el de la tabla `estudiantes` de **ese** tenant. El padre
tiene que estar vinculado a ese mismo id. Un vínculo de Jean Piaget no ve
eventos de `asis_academy`.

---

## Ejemplos (Jean Piaget)

Sustituye `INGEST_KEY` y la URL. `tenant_id` fijo: `jean_piaget`.

### Entrada

```bash
curl -sS -X POST "http://192.168.18.206:8000/v0.1/ingesta/eventos" \
  -H "Content-Type: application/json" \
  -H "X-Asiscole-Ingest-Key: INGEST_KEY" \
  -d "{
    \"tenant_id\": \"jean_piaget\",
    \"tipo\": \"entrada\",
    \"id_estudiante\": 10,
    \"id_registro\": 1042,
    \"payload\": {
      \"id_estudiante\": 10,
      \"nombre_completo\": \"Ana Pérez\",
      \"grado\": \"3\",
      \"seccion\": \"A\",
      \"nivel_educativo\": \"Primaria\",
      \"fecha\": \"2026-07-26\",
      \"hora_llegada\": \"07:45\",
      \"estado\": \"A tiempo\"
    }
  }"
```

### Salida

```bash
curl -sS -X POST "http://192.168.18.206:8000/v0.1/ingesta/eventos" \
  -H "Content-Type: application/json" \
  -H "X-Asiscole-Ingest-Key: INGEST_KEY" \
  -d "{
    \"tenant_id\": \"jean_piaget\",
    \"tipo\": \"salida\",
    \"id_estudiante\": 10,
    \"id_registro\": 1042,
    \"payload\": {
      \"id_estudiante\": 10,
      \"nombre_completo\": \"Ana Pérez\",
      \"grado\": \"3\",
      \"seccion\": \"A\",
      \"nivel_educativo\": \"Primaria\",
      \"fecha\": \"2026-07-26\",
      \"hora_salida\": \"15:10\",
      \"tipo_salida\": \"Normal\"
    }
  }"
```

### Incidencia / reporte

```bash
curl -sS -X POST "http://192.168.18.206:8000/v0.1/ingesta/eventos" \
  -H "Content-Type: application/json" \
  -H "X-Asiscole-Ingest-Key: INGEST_KEY" \
  -d "{
    \"tenant_id\": \"jean_piaget\",
    \"tipo\": \"incidencia\",
    \"id_estudiante\": 10,
    \"id_registro\": 55,
    \"payload\": {
      \"id_estudiante\": 10,
      \"nombre_completo\": \"Ana Pérez\",
      \"grado\": \"3\",
      \"seccion\": \"A\",
      \"nivel_educativo\": \"Primaria\",
      \"fecha\": \"2026-07-26\",
      \"hora\": \"10:30\",
      \"id_falta\": 1,
      \"nombre_falta\": \"Uso de celular en clase\",
      \"categoria\": \"Disciplina\",
      \"es_grave\": false,
      \"nombre_usuario_registro\": \"Rosa Quispe Mamani\"
    }
  }"
```

### Desde el SIE (TypeScript / fetch)

```ts
await fetch(`${CANAL_BASE_URL}/v0.1/ingesta/eventos`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "X-Asiscole-Ingest-Key": process.env.ASISCOLE_INGEST_API_KEY!,
  },
  body: JSON.stringify({
    tenant_id: "jean_piaget",
    tipo: "entrada", // o salida | incidencia | aviso | nota
    id_estudiante: record.studentId,
    id_registro: record.id,
    payload: {
      id_estudiante: record.studentId,
      nombre_completo: student.fullName,
      grado: student.grade,
      seccion: student.section,
      nivel_educativo: student.level,
      fecha: record.date, // YYYY-MM-DD
      hora_llegada: record.arrivalTime, // HH:MM
      estado: record.status, // "A tiempo" | "Tarde"
    },
  }),
});
```

Cuándo llamarlo en el SIE: **después** de guardar bien en Supabase (entrada INSERT, salida UPDATE con `hora_salida`, incidencia INSERT). Si el POST al canal falla, el registro escolar **no** se revierte; reintentar o usar outbox.

---

## Qué ve el apoderado

| Tras la ingesta | Dónde |
|-----------------|--------|
| Mensaje de texto + push | Tab **Mensajes** (`entrada`, `salida`, `incidencia`, `aviso`) |
| Calendario llegada/salida | Tab **Asistencias** (lee la BD del colegio, no el POST) |
| Listado de reportes | Tab **Incidencias** (lee la BD del colegio) |
| Nota semanal | Tab **Notas** (lee `asis_nota` en la BD central) |

Por eso el SIE debe **seguir guardando** en su BD y **además** avisar al canal.
Si solo llama a la API y no escribe en `registros_llegada` / `incidencias`,
Mensajes sí y Asistencias/Incidencias no. Las notas son al revés: el canal
**sí** persiste `asis_nota`; no lee `notas_semana` del colegio.

### Condiciones para `creados >= 1`

1. `tenant_id` configurado en `SCHOOL_DATABASES` del canal.
2. Estudiante con `telefono_contacto` válido (o varios separados por `/`).
3. Ese vínculo en `asis_directorio` (login del apoderado o reconciliación).
4. Cuenta de apoderado activa con ese teléfono.

Para `tipo: nota` la fila se guarda aunque aún no haya apoderado; el historial
queda listo para cuando el padre se vincule. El push solo sale si hay cuenta.

---

## Academy — citas y notas

Jean Piaget y San Ramón no se tocan. En Academy el flag del SIE vive fuera de
este repo (`/opt/sie-academy/.env.build`):

```
VITE_MOBILE_INGEST_ENABLED=true
VITE_MOBILE_INGEST_URL=/canal-api
VITE_MOBILE_INGEST_TENANT=asis_academy
```

Tras rebuild del frontend de Academy, Caddy reenvía `/canal-api*` al Django.
El POST queda:

`https://demostracion.asisacademy.com/canal-api/v0.1/ingesta/eventos`

En el canal hay que activar el módulo para que la app muestre la pestaña:

```sql
UPDATE public.asis_feature_flag SET activo = true WHERE clave = 'notas';
```

### Cita → bandeja (`tipo: aviso`, `contexto: cita`)

Solo al **crear** (individual o masiva). `id_registro` = `citas_padres.id_cita`.

```bash
curl -sS -X POST "$BASE/v0.1/ingesta/eventos" \
  -H "Content-Type: application/json" \
  -H "X-Asiscole-Ingest-Key: INGEST_KEY" \
  -d "{
    \"tenant_id\": \"asis_academy\",
    \"tipo\": \"aviso\",
    \"id_estudiante\": 10,
    \"id_registro\": 44,
    \"payload\": {
      \"nombre_completo\": \"Ana Pérez\",
      \"grado\": \"2003\",
      \"seccion\": \"5\",
      \"nivel_educativo\": \"Pre-universitario\",
      \"contexto\": \"cita\",
      \"fecha\": \"2026-08-20\",
      \"hora\": \"09:30\",
      \"motivo\": \"Revisión de incidencias\",
      \"alcance\": \"individual\",
      \"texto_libre\": \"Se citó a los padres de Ana Pérez el 20/08/2026 a las 09:30. Motivo: …\"
    }
  }"
```

Comprobarlo: crear una cita en el SIE con «Notificar por la aplicación» y ver el
aviso en el padre de ese alumno.

### Nota → sección (`tipo: nota`)

`id_registro` = `notas_semana.id`. No crea mensaje en la bandeja.

```bash
curl -sS -X POST "$BASE/v0.1/ingesta/eventos" \
  -H "Content-Type: application/json" \
  -H "X-Asiscole-Ingest-Key: INGEST_KEY" \
  -d "{
    \"tenant_id\": \"asis_academy\",
    \"tipo\": \"nota\",
    \"id_estudiante\": 10,
    \"id_registro\": 991,
    \"payload\": {
      \"semana_codigo\": \"2026-02\",
      \"semana_etiqueta\": \"Semana 2\",
      \"fecha_inicio\": \"2026-02-03\",
      \"fecha_fin\": \"2026-02-09\",
      \"nota\": \"18.5\",
      \"nota_maxima\": \"20\",
      \"area_codigo\": \"salud\",
      \"area_nombre\": \"Ciencias de la Salud\",
      \"carrera\": \"Medicina Humana\",
      \"registrado_en\": \"2026-08-15T15:00:00-05:00\",
      \"texto_libre\": \"Se registró la nota semanal de Ana Pérez: 18.5/20 (Semana 2).\"
    }
  }"
```

Comprobarlo: importar Excel de notas en el SIE y ver la fila en **Notas** del
hijo, no un texto en la bandeja.

El RPC `sie_notas_por_estudiante` (script del colegio
`08_NOTAS_POR_ESTUDIANTE.sql`) no lo llama el SIE ni este canal: sirve para
hidratar o reconciliar si más adelante se conecta un backend con sesión contra
el Supabase de Academy. El historial de la app se llena al vuelo con cada ingest.

---

## Alternativa sin tocar el web

Triggers + `asis_outbox` en la BD del colegio (`001_colegio_outbox.sql`) y poller Celery. La ingesta HTTP es la vía preferida cuando el SIE puede hacer el POST.
