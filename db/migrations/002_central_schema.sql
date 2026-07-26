-- =============================================================================
-- 002_central_schema.sql - SE EJECUTA EN LA BASE DE DATOS CENTRAL DEL CANAL
-- =============================================================================
-- PostgreSQL propio del canal apoderado (NO es Supabase, no hay PostgREST ni RLS
-- de por medio: el unico cliente es el backend Django).
--
-- QUIEN MANDA: Django es el dueno del esquema. En produccion estas tablas las crean
-- y evolucionan las migraciones de Django. Este archivo es la REFERENCIA CANONICA
-- del modelo y sirve para levantar la base a mano (entorno local, revision del
-- modelo, recuperacion). Si Django y este archivo divergen, gana Django y hay que
-- actualizar este archivo en el mismo PR.
--
-- Convenciones: todo objeto lleva prefijo asis_, comentarios en espanol, zona
-- horaria America/Lima (los TIMESTAMPTZ se guardan en UTC y se formatean en Lima
-- en la capa de aplicacion). Script idempotente.
-- =============================================================================

BEGIN;

-- gen_random_uuid() es nativa desde PostgreSQL 13; pgcrypto se instala por si la
-- base central corre sobre una version anterior.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- asis_apoderado - la cuenta del canal
-- -----------------------------------------------------------------------------
-- El telefono en E.164 (+51987654321) es la identidad. No hay contrasena: el login
-- es telefono + codigo del estudiante (estudiantes.codigo_barras del colegio).
CREATE TABLE IF NOT EXISTS public.asis_apoderado (
  id                BIGSERIAL   PRIMARY KEY,
  telefono          TEXT        NOT NULL UNIQUE,
  nombre_alias      TEXT        NULL,
  estado            TEXT        NOT NULL DEFAULT 'activo'
                                CHECK (estado IN ('activo', 'suspendido', 'eliminado')),
  motivo_suspension TEXT        NULL,
  suspendido_en     TIMESTAMPTZ NULL,
  estudiante_activo_id     INTEGER NULL,
  estudiante_activo_tenant TEXT    NULL,
  creado_en         TIMESTAMPTZ NOT NULL DEFAULT now(),
  actualizado_en    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.asis_apoderado IS
  'Cuenta del apoderado en el canal movil. Identidad = telefono en E.164.';
COMMENT ON COLUMN public.asis_apoderado.telefono IS
  'Telefono normalizado a E.164 (+51XXXXXXXXX). Unico en todo el canal.';
COMMENT ON COLUMN public.asis_apoderado.estado IS
  '"eliminado" corresponde a la baja de cuenta (RF-I06): los datos del apoderado se '
  'anonimizan y se revocan sesiones y push. El expediente del estudiante en la BD '
  'del colegio no se toca.';

-- -----------------------------------------------------------------------------
-- asis_directorio - que estudiantes cuelgan de que telefono, y en que colegio
-- -----------------------------------------------------------------------------
-- Se alimenta de la vista asis_v_directorio_origen de cada BD de colegio (ver 001).
-- tenant_id identifica el colegio; es la unica forma de saber a que base pertenece
-- id_estudiante, porque los IDs se repiten entre colegios.
CREATE TABLE IF NOT EXISTS public.asis_directorio (
  id                BIGSERIAL   PRIMARY KEY,
  telefono          TEXT        NOT NULL,
  tenant_id         TEXT        NOT NULL,
  id_estudiante     INTEGER     NOT NULL,
  codigo_barras     TEXT        NOT NULL,
  nombre_estudiante TEXT        NOT NULL,
  grado             TEXT        NULL,
  seccion           TEXT        NULL,
  nivel             TEXT        NULL,
  relacion          TEXT        NULL DEFAULT 'apoderado',
  origen            TEXT        NULL CHECK (origen IN ('resuelto_automatico', 'registrado_admin')),
  estado_vinculo    TEXT        NULL DEFAULT 'activo',
  sincronizado_en   TIMESTAMPTZ NULL,
  CONSTRAINT asis_directorio_unico UNIQUE (telefono, tenant_id, id_estudiante)
);

-- El login y la bandeja resuelven "que estudiantes tiene este telefono" en cada
-- request; este indice es el camino caliente.
CREATE INDEX IF NOT EXISTS asis_idx_directorio_telefono
  ON public.asis_directorio (telefono);

COMMENT ON TABLE public.asis_directorio IS
  'Vinculo telefono <-> estudiante <-> colegio. Replica minima del dato del colegio, '
  'solo lo que el canal necesita para enrutar mensajes y armar la lista de hijos.';
COMMENT ON COLUMN public.asis_directorio.tenant_id IS
  'Identificador del colegio (una BD Supabase por colegio).';
COMMENT ON COLUMN public.asis_directorio.origen IS
  '"resuelto_automatico": salio de estudiantes.telefono_contacto. '
  '"registrado_admin": lo cargo un administrador del canal.';

-- -----------------------------------------------------------------------------
-- asis_sesion_activa - un solo dispositivo por cuenta (RNF-02)
-- -----------------------------------------------------------------------------
-- La sesion del canal dura 10 dias y esta atada a un device_id. Nada que ver con
-- public.app_sesiones del sistema web (15 min, sin device_id), que vive en la BD
-- del colegio y no se toca.
CREATE TABLE IF NOT EXISTS public.asis_sesion_activa (
  id                 BIGSERIAL   PRIMARY KEY,
  apoderado_id       BIGINT      NOT NULL REFERENCES public.asis_apoderado(id) ON DELETE CASCADE,
  device_id          TEXT        NOT NULL,
  jti                UUID        NOT NULL UNIQUE,
  modelo             TEXT        NULL,
  sistema_operativo  TEXT        NULL,
  estado             TEXT        NOT NULL DEFAULT 'active',
  creada_en          TIMESTAMPTZ NOT NULL DEFAULT now(),
  ultima_actividad_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  expira_en          TIMESTAMPTZ NOT NULL
);

-- CRITICO (RNF-02): la base garantiza una unica sesion activa por apoderado. Un
-- segundo login se deniega con 409; NO reemplaza la sesion existente. Al cerrar o
-- transferir, la sesion anterior pasa a un estado distinto de 'active' y libera el
-- indice. No usar ON CONFLICT para "pisar" la sesion: la regla es denegar.
CREATE UNIQUE INDEX IF NOT EXISTS asis_uniq_sesion_activa
  ON public.asis_sesion_activa (apoderado_id)
  WHERE estado = 'active';

CREATE INDEX IF NOT EXISTS asis_idx_sesion_expira
  ON public.asis_sesion_activa (expira_en)
  WHERE estado = 'active';

COMMENT ON COLUMN public.asis_sesion_activa.jti IS
  'Identificador del token emitido. Permite revocar sin guardar el JWT.';
COMMENT ON COLUMN public.asis_sesion_activa.estado IS
  'active | revocada | expirada | transferida. Solo "active" ocupa el indice unico.';

-- -----------------------------------------------------------------------------
-- asis_transferencia_sesion - cambio de dispositivo autorizado
-- -----------------------------------------------------------------------------
-- El equipo nuevo pide la transferencia y el equipo con la sesion viva la aprueba
-- o la rechaza. TTL de 5 minutos: pasado ese plazo la solicitud queda 'expired'.
CREATE TABLE IF NOT EXISTS public.asis_transferencia_sesion (
  id             BIGSERIAL   PRIMARY KEY,
  apoderado_id   BIGINT      NOT NULL REFERENCES public.asis_apoderado(id) ON DELETE CASCADE,
  from_device_id TEXT        NULL,
  to_device_id   TEXT        NOT NULL,
  estado         TEXT        NOT NULL DEFAULT 'pending'
                             CHECK (estado IN ('pending', 'approved', 'rejected', 'expired')),
  creada_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expira_en      TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '5 minutes')
);

-- Una sola solicitud pendiente por apoderado: evita que varios equipos inunden de
-- pedidos al dispositivo que tiene la sesion.
CREATE UNIQUE INDEX IF NOT EXISTS asis_uniq_transferencia_pendiente
  ON public.asis_transferencia_sesion (apoderado_id)
  WHERE estado = 'pending';

-- -----------------------------------------------------------------------------
-- asis_push_token - token de notificaciones por dispositivo
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asis_push_token (
  id             BIGSERIAL   PRIMARY KEY,
  apoderado_id   BIGINT      NOT NULL REFERENCES public.asis_apoderado(id) ON DELETE CASCADE,
  device_id      TEXT        NOT NULL,
  token          TEXT        NOT NULL,
  plataforma     TEXT        NULL CHECK (plataforma IN ('android', 'ios')),
  activo         BOOLEAN     NOT NULL DEFAULT true,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT asis_push_token_unico UNIQUE (apoderado_id, device_id)
);

COMMENT ON TABLE public.asis_push_token IS
  'Un token por (apoderado, dispositivo). Al reinstalar la app se hace UPSERT sobre '
  'la clave unica. La baja de cuenta desactiva o borra estas filas.';

-- -----------------------------------------------------------------------------
-- asis_mensaje - la bandeja del apoderado
-- -----------------------------------------------------------------------------
-- El backend genera el texto; el cliente solo renderiza. El id UUID viaja como
-- message_id en el push y da idempotencia al cliente (si llega dos veces, se
-- muestra una sola vez).
CREATE TABLE IF NOT EXISTS public.asis_mensaje (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  apoderado_id   BIGINT      NOT NULL REFERENCES public.asis_apoderado(id) ON DELETE CASCADE,
  tenant_id      TEXT        NOT NULL,
  id_estudiante  INTEGER     NULL,
  tipo           TEXT        NOT NULL
                             CHECK (tipo IN ('entrada', 'salida', 'incidencia', 'aviso', 'personalizado')),
  texto          TEXT        NOT NULL,
  metadata       JSONB       NOT NULL DEFAULT '{}'::jsonb,
  origen_evento  TEXT        NULL,
  emitido_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  entregado      BOOLEAN     NOT NULL DEFAULT false,
  entregado_en   TIMESTAMPTZ NULL,
  leido          BOOLEAN     NOT NULL DEFAULT false,
  leido_en       TIMESTAMPTZ NULL,
  retenido_hasta TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 months')
);

-- Bandeja: mensajes de un apoderado, del mas nuevo al mas viejo.
CREATE INDEX IF NOT EXISTS asis_idx_mensaje_bandeja
  ON public.asis_mensaje (apoderado_id, emitido_en DESC);

-- Purga por retencion (MESSAGE_RETENTION_MONTHS, Ley N.o 29733).
CREATE INDEX IF NOT EXISTS asis_idx_mensaje_retencion
  ON public.asis_mensaje (retenido_hasta);

-- IDEMPOTENCIA DE LA INGESTA: origen_evento es la huella del evento de origen,
-- construida como '<tipo>:<id_registro>' con los datos de asis_outbox del colegio.
-- No se usa metadata->>'id_registro' en la clave unica porque una expresion sobre
-- JSONB no da una restriccion declarativa manejable desde Django y se rompe si el
-- metadata cambia de forma. El indice es parcial porque los mensajes que no nacen
-- de un evento (avisos, personalizados) llevan origen_evento NULL y pueden repetirse.
CREATE UNIQUE INDEX IF NOT EXISTS asis_uniq_mensaje_origen
  ON public.asis_mensaje (apoderado_id, tenant_id, origen_evento)
  WHERE origen_evento IS NOT NULL;

COMMENT ON COLUMN public.asis_mensaje.origen_evento IS
  'Huella del evento del colegio, p. ej. "entrada:1042". Unico por apoderado+tenant: '
  'evita duplicar el mensaje si el poller reprocesa una fila de asis_outbox.';
COMMENT ON COLUMN public.asis_mensaje.texto IS
  'Texto final generado por el backend. El cliente no compone mensajes.';
COMMENT ON COLUMN public.asis_mensaje.retenido_hasta IS
  'Fecha de purga o anonimizacion (24 meses desde la emision).';

-- -----------------------------------------------------------------------------
-- asis_intento_login - control de fuerza bruta
-- -----------------------------------------------------------------------------
-- PRIVACIDAD (Ley N.o 29733): en "clave" va SIEMPRE un hash de (telefono + codigo
-- del estudiante), NUNCA el telefono ni el codigo_barras en claro. Esta tabla existe
-- para contar intentos, no para saber quien los hizo. La respuesta al cliente es
-- siempre STUDENT_LINK_NOT_FOUND, sin distinguir que dato fallo.
CREATE TABLE IF NOT EXISTS public.asis_intento_login (
  id         BIGSERIAL   PRIMARY KEY,
  clave      TEXT        NOT NULL,
  ip         TEXT        NULL,
  exitoso    BOOLEAN     NOT NULL DEFAULT false,
  ocurrido_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS asis_idx_intento_login_clave
  ON public.asis_intento_login (clave, ocurrido_en);

COMMENT ON COLUMN public.asis_intento_login.clave IS
  'Hash (p. ej. SHA-256 con sal del servidor) de telefono+codigo. Prohibido guardar '
  'el telefono o el codigo_barras en claro.';

-- -----------------------------------------------------------------------------
-- asis_feature_flag - interruptores de modulo
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asis_feature_flag (
  clave          TEXT        PRIMARY KEY,
  activo         BOOLEAN     NOT NULL DEFAULT false,
  descripcion    TEXT        NULL,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.asis_feature_flag (clave, activo, descripcion)
VALUES ('notas', false, 'Modulo de notas - RF-H')
ON CONFLICT (clave) DO NOTHING;

-- -----------------------------------------------------------------------------
-- asis_auditoria - rastro de acciones del canal
-- -----------------------------------------------------------------------------
-- detalle es JSONB tecnico: request_id, device_id, resultado. Nunca contenido de
-- mensajes, nombres de estudiantes, telefonos ni codigo_barras.
CREATE TABLE IF NOT EXISTS public.asis_auditoria (
  id           BIGSERIAL   PRIMARY KEY,
  apoderado_id BIGINT      NULL REFERENCES public.asis_apoderado(id) ON DELETE SET NULL,
  actor        TEXT        NULL,
  accion       TEXT        NOT NULL,
  detalle      JSONB       NULL,
  request_id   TEXT        NULL,
  ocurrido_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS asis_idx_auditoria_accion
  ON public.asis_auditoria (accion, ocurrido_en);

COMMENT ON COLUMN public.asis_auditoria.detalle IS
  'Solo datos tecnicos. La correlacion se hace con request_id e identificadores '
  'internos, jamas con datos personales del menor o del apoderado.';

-- -----------------------------------------------------------------------------
-- asis_cursor_ingesta - progreso del poller por colegio
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asis_cursor_ingesta (
  tenant_id      TEXT        PRIMARY KEY,
  ultimo_id      BIGINT      NOT NULL DEFAULT 0,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.asis_cursor_ingesta IS
  'Ultimo id de asis_outbox procesado por colegio.';

COMMIT;
