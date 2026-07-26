# API de ingesta — SIE Asiscole → canal apoderado

Para que el sistema web de asistencias e incidencias (Jean Piaget u otro colegio)
avise al backend del canal cuando registra una **entrada**, **salida** o **incidencia**.

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
| `tipo` | string | sí | `entrada` \| `salida` \| `incidencia` |
| `id_estudiante` | int | sí | PK en la BD del colegio |
| `id_registro` | int | sí | PK de `registros_llegada` o `incidencias` (idempotencia) |
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

- `creados: 0` → el evento se aceptó pero **no hay apoderado vinculado** en `asis_directorio` + cuenta activa. Revisa teléfono del estudiante y login previo del apoderado.
- Mismo `(tipo, id_registro)` otra vez → no duplica mensajes.

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
    tipo: "entrada", // o salida | incidencia
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
| Mensaje de texto + push | Tab **Mensajes** de la app |
| Calendario llegada/salida | Tab **Asistencias** (lee la BD del colegio, no el POST) |
| Listado de reportes | Tab **Incidencias** (lee la BD del colegio) |

Por eso el SIE debe **seguir guardando** en su BD y **además** avisar al canal. Si solo llama a la API y no escribe en `registros_llegada` / `incidencias`, Mensajes sí y Asistencias/Incidencias no.

### Condiciones para `creados >= 1`

1. `tenant_id` = `jean_piaget` en `SCHOOL_DATABASES`.
2. Estudiante con `telefono_contacto` válido (o varios separados por `/`).
3. Ese vínculo en `asis_directorio` (login del apoderado o reconciliación).
4. Cuenta de apoderado activa con ese teléfono.

---

## Alternativa sin tocar el web

Triggers + `asis_outbox` en la BD del colegio (`001_colegio_outbox.sql`) y poller Celery. La ingesta HTTP es la vía preferida cuando el SIE puede hacer el POST.
