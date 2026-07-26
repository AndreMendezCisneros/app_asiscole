-- =============================================================================
-- ESQUEMA DEL COLEGIO — REFERENCIA ESTRUCTURAL. NO EJECUTAR.
-- =============================================================================
-- Extracto fiel de la estructura del bootstrap real de Asiscole/SIE por colegio
-- (Supabase/PostgreSQL, zona horaria America/Lima). Se conserva aqui para que el
-- backend del canal conozca nombres exactos de tablas, columnas y RPCs.
--
-- El canal NO modifica nada de este esquema. Todo lo nuevo va en
-- db/migrations con prefijo asis_.
--
-- Se omiten los cuerpos de las funciones PL/pgSQL: solo interesan las firmas.
-- =============================================================================

-- Extensiones ----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Enums ----------------------------------------------------------------------
-- rol_usuario       : 'Admin' | 'Director' | 'Supervisor' | 'Tutor' | 'Padre' | 'Docente'
-- nivel_educativo   : 'Primaria' | 'Secundaria'
-- estado_incidencia : 'Activa' | 'Anulada' | 'En revisión' | 'Justificada'
-- estado_evidencia  : 'Sin evidencia' | 'Con evidencia'

-- =============================================================================
-- TABLAS
-- =============================================================================

CREATE TABLE public.usuarios (
  id_usuario                  SERIAL PRIMARY KEY,
  username                    VARCHAR(50) NOT NULL UNIQUE,
  password_hash               TEXT NOT NULL,          -- bcrypt ($2...) via extensions.crypt
  nombre_completo             VARCHAR(255) NOT NULL,
  email                       VARCHAR(255) NOT NULL,
  rol                         public.rol_usuario NOT NULL,
  grados_asignados            JSONB DEFAULT NULL,     -- {"classrooms":[{level,grade,section}]}
  activo                      BOOLEAN NOT NULL DEFAULT true,
  cambio_password_obligatorio BOOLEAN NOT NULL DEFAULT false,
  ultimo_acceso               TIMESTAMPTZ NULL,
  intentos_fallidos           INTEGER NOT NULL DEFAULT 0,
  bloqueado_hasta             TIMESTAMPTZ NULL,
  fecha_creacion              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- CLAVE PARA EL CANAL: codigo_barras es el "DNI del estudiante" del login (RF-A01).
-- telefono_contacto es el telefono del apoderado, en texto libre (normalizar a E.164).
CREATE TABLE public.estudiantes (
  id_estudiante          SERIAL PRIMARY KEY,
  codigo_barras          VARCHAR(50) NOT NULL UNIQUE,
  nombre_completo        VARCHAR(255) NOT NULL,
  grado                  VARCHAR(20) NOT NULL,
  seccion                VARCHAR(10) NOT NULL,
  nivel_educativo        public.nivel_educativo NOT NULL,
  foto_perfil            TEXT NULL,
  activo                 BOOLEAN NOT NULL DEFAULT true,
  telefono_contacto      VARCHAR(20) NULL,
  email_contacto         VARCHAR(255) NULL,
  nombre_responsable     VARCHAR(255) NULL,
  parentesco_responsable VARCHAR(50) NULL,
  telefono_emergencia    VARCHAR(20) NULL,
  fecha_creacion         TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_actualizacion    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- idx_estudiantes_telefono_contacto ON (telefono_contacto) WHERE telefono_contacto IS NOT NULL

CREATE TABLE public.catalogo_faltas (
  id_falta            SERIAL PRIMARY KEY,
  nombre_falta        VARCHAR(255) NOT NULL,
  categoria           TEXT NOT NULL,
  es_grave            BOOLEAN NOT NULL DEFAULT false,
  puntos_reincidencia INTEGER NOT NULL DEFAULT 1,
  descripcion         TEXT NULL,
  activo              BOOLEAN NOT NULL DEFAULT true,
  orden_visualizacion INTEGER NOT NULL DEFAULT 0,
  fecha_creacion      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.incidencias (
  id_incidencia          SERIAL PRIMARY KEY,
  id_estudiante          INTEGER NOT NULL REFERENCES public.estudiantes(id_estudiante) ON DELETE CASCADE,
  id_falta               INTEGER NOT NULL REFERENCES public.catalogo_faltas(id_falta),
  fecha_hora_registro    TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_usuario_registro    INTEGER NOT NULL REFERENCES public.usuarios(id_usuario),
  nivel_reincidencia     INTEGER NOT NULL DEFAULT 0,   -- lo calcula un trigger BEFORE INSERT
  observaciones          TEXT NULL,
  estado_evidencia       public.estado_evidencia NOT NULL DEFAULT 'Sin evidencia',
  cantidad_fotos         INTEGER NOT NULL DEFAULT 0,
  id_usuario_carga_foto  INTEGER NULL REFERENCES public.usuarios(id_usuario),
  fecha_hora_carga_foto  TIMESTAMPTZ NULL,
  estado                 public.estado_incidencia NOT NULL DEFAULT 'Activa',
  motivo_anulacion       TEXT NULL,
  id_usuario_anulacion   INTEGER NULL REFERENCES public.usuarios(id_usuario),
  fecha_anulacion        TIMESTAMPTZ NULL,
  veces_impreso          INTEGER NOT NULL DEFAULT 0,
  fecha_ultima_impresion TIMESTAMPTZ NULL
);

CREATE TABLE public.evidencias_fotograficas (
  id_evidencia         SERIAL PRIMARY KEY,
  id_incidencia        INTEGER NOT NULL REFERENCES public.incidencias(id_incidencia) ON DELETE CASCADE,
  ruta_archivo         TEXT NOT NULL,
  nombre_original      TEXT NOT NULL,
  nombre_archivo       TEXT NOT NULL,
  tamano_bytes         INTEGER NOT NULL,
  tipo_mime            VARCHAR(100) NOT NULL,
  id_usuario_subida    INTEGER NOT NULL REFERENCES public.usuarios(id_usuario),
  fecha_subida         TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_subida            VARCHAR(50) NULL,
  marca_agua_aplicada  BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE public.comentarios_incidencias (
  id_comentario    SERIAL PRIMARY KEY,
  id_incidencia    INTEGER NOT NULL REFERENCES public.incidencias(id_incidencia) ON DELETE CASCADE,
  id_usuario       INTEGER NOT NULL REFERENCES public.usuarios(id_usuario),
  texto_comentario TEXT NOT NULL,
  fecha_hora       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- CLAVE PARA EL CANAL: la entrada es un INSERT; la salida es un UPDATE de hora_salida.
-- No existen filas para "Falta" ni "Sin registro": se derivan por ausencia de fila.
CREATE TABLE public.registros_llegada (
  id_registro           SERIAL PRIMARY KEY,
  id_estudiante         INTEGER NOT NULL REFERENCES public.estudiantes(id_estudiante) ON DELETE CASCADE,
  fecha                 DATE NOT NULL,
  hora_llegada          TIME NOT NULL,
  estado                VARCHAR(20) NOT NULL CHECK (estado IN ('A tiempo', 'Tarde')),
  registrado_por        INTEGER NULL REFERENCES public.usuarios(id_usuario),
  fecha_creacion        TIMESTAMPTZ NOT NULL DEFAULT now(),
  hora_salida           TIME NULL,
  registrado_salida_por INTEGER NULL REFERENCES public.usuarios(id_usuario) ON DELETE SET NULL,
  fecha_salida          TIMESTAMPTZ NULL,
  tipo_salida           VARCHAR(20) NULL CHECK (tipo_salida IS NULL OR tipo_salida IN ('Normal', 'Autorizada', 'Sin registro')),
  CONSTRAINT registros_llegada_estudiante_fecha_unique UNIQUE (id_estudiante, fecha)
);

CREATE TABLE public.configuracion_sistema (
  id_config           SERIAL PRIMARY KEY,
  clave               VARCHAR(100) NOT NULL UNIQUE,
  valor               TEXT NOT NULL,
  descripcion         TEXT NULL,
  fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Claves sembradas: hora_limite_llegada, hora_limite_llegada_primaria,
-- hora_limite_llegada_secundaria, hora_limite_salida, hora_cierre_colegio,
-- categorias_faltas

CREATE TABLE public.configuracion_reincidencia (
  id_config_reincidencia SERIAL PRIMARY KEY,
  ventana_dias           INTEGER NOT NULL DEFAULT 60,
  puntos_falta_leve      INTEGER NOT NULL DEFAULT 1,
  puntos_falta_grave     INTEGER NOT NULL DEFAULT 2,
  umbral_nivel_1         INTEGER NOT NULL DEFAULT 1,
  umbral_nivel_2         INTEGER NOT NULL DEFAULT 3,
  umbral_nivel_3         INTEGER NOT NULL DEFAULT 5,
  umbral_nivel_4         INTEGER NOT NULL DEFAULT 8,
  umbral_nivel_5         INTEGER NOT NULL DEFAULT 12,
  activo                 BOOLEAN NOT NULL DEFAULT true,
  fecha_vigencia         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.auditoria_logs (
  id_log             SERIAL PRIMARY KEY,
  id_usuario         INTEGER NULL REFERENCES public.usuarios(id_usuario),
  tabla_afectada     VARCHAR(100) NOT NULL,
  id_registro        INTEGER NOT NULL DEFAULT 0,
  accion             VARCHAR(20) NOT NULL CHECK (accion IN ('INSERT', 'UPDATE', 'DELETE')),
  datos_anteriores   JSONB NULL,
  datos_nuevos       JSONB NULL,
  descripcion_accion TEXT NULL,
  ip_address         VARCHAR(50) NULL,
  user_agent         TEXT NULL,
  fecha_hora         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.citas_padres (
  id_cita             SERIAL PRIMARY KEY,
  id_estudiante       INTEGER NOT NULL REFERENCES public.estudiantes(id_estudiante) ON DELETE CASCADE,
  motivo              VARCHAR(255) NOT NULL,
  fecha               DATE NOT NULL,
  hora                TIME NOT NULL,
  estado              VARCHAR(20) NOT NULL DEFAULT 'Pendiente',
  asistencia          BOOLEAN DEFAULT NULL,
  llegada_tarde       BOOLEAN DEFAULT NULL,
  hora_llegada_real   TIME DEFAULT NULL,
  notas               TEXT NULL,
  id_usuario_creador  INTEGER NOT NULL REFERENCES public.usuarios(id_usuario),
  fecha_creacion      TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- CLAVE PARA EL CANAL: vinculo apoderado-estudiante ya existente. Se reutiliza.
CREATE TABLE public.padres_estudiantes (
  id_relacion    SERIAL PRIMARY KEY,
  id_usuario     INTEGER NOT NULL REFERENCES public.usuarios(id_usuario) ON DELETE CASCADE,
  id_estudiante  INTEGER NOT NULL REFERENCES public.estudiantes(id_estudiante) ON DELETE CASCADE,
  parentesco     VARCHAR(50) DEFAULT 'Apoderado',
  es_principal   BOOLEAN DEFAULT true,
  fecha_creacion TIMESTAMPTZ DEFAULT now(),
  UNIQUE (id_usuario, id_estudiante)
);

-- ATENCION: sesion del sistema web (15 min para rol Padre). NO la usa el canal movil,
-- que necesita 10 dias y device_id. El canal lleva su propio almacen en la BD central.
CREATE TABLE public.app_sesiones (
  id_sesion  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash text NOT NULL UNIQUE,
  id_usuario integer NOT NULL REFERENCES public.usuarios(id_usuario) ON DELETE CASCADE,
  rol        text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.tokens_recuperacion (
  id_token         SERIAL PRIMARY KEY,
  id_usuario       INTEGER NOT NULL REFERENCES public.usuarios(id_usuario) ON DELETE CASCADE,
  token_hash       TEXT NOT NULL,
  fecha_expiracion TIMESTAMPTZ NOT NULL,
  usado            BOOLEAN NOT NULL DEFAULT false,
  fecha_creacion   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- VISTAS
-- =============================================================================
-- v_estudiantes_nivel_actual (security_invoker)
--   -> id_estudiante, nivel_actual, total_faltas_60_dias
-- v_dashboard_ejecutivo (security_invoker)
--   -> total_incidencias_mes, estudiantes_afectados_mes

-- =============================================================================
-- FUNCIONES Y RPCs (firmas)
-- =============================================================================
-- Sesion / auth del sistema web:
--   _sie_token_hash(text) -> text
--   _sie_validar_token(text) -> TABLE(id_usuario int, rol text)
--   _sie_es_staff(text) -> boolean               -- Admin | Director | Supervisor
--   sie_request_token() -> text                  -- lee el header x-sie-token
--   sie_sesion_rol() -> text
--   sie_sesion_usuario_id() -> integer
--   sie_tiene_sesion() -> boolean
--   sie_es_staff_sesion() -> boolean
--   validar_password(text, text) -> boolean
--   sie_iniciar_sesion(text, text) -> jsonb
--   sie_cerrar_sesion(text) -> void
--   sie_renovar_sesion(text) -> jsonb
--   sie_solicitar_reset_password(text) -> jsonb
--   sie_cambiar_password(text, text) -> jsonb
--
-- Permisos de visibilidad:
--   _sie_ids_estudiantes_padre(int) -> int[]
--   _sie_padre_puede_ver_estudiante_uid(int, int) -> boolean
--   sie_padre_puede_ver_estudiante(int) -> boolean
--   _sie_docente_puede_ver_estudiante(int) -> boolean
--
-- Estudiantes:
--   sie_buscar_estudiante_carnet(text, text, boolean) -> jsonb
--   sie_buscar_estudiantes_nombre(text, text, int) -> jsonb
--   sie_lista_estudiantes(text, jsonb) -> jsonb
--   sie_estudiante_por_id(text, int) -> jsonb
--   sie_padre_mis_estudiantes(text) -> jsonb
--   sie_crear_estudiante(text, jsonb) -> jsonb
--   sie_actualizar_estudiante(text, int, jsonb) -> jsonb
--
-- Asistencia (las usa el portal publico de padres):
--   buscar_asistencia_por_dni(text) -> jsonb      -- compara contra codigo_barras
--   asistencia_mes_por_estudiante(int, int, int) -> jsonb
--   limites_llegada_publicos() -> jsonb
--   _sie_hora_limite_por_nivel(text) -> text
--   _sie_estado_llegada(text, text) -> text       -- 'A tiempo' | 'Tarde'
--
-- Incidencias y evidencias:
--   calcular_nivel_reincidencia(int, timestamptz) -> integer
--   anular_incidencia(int, int, text) -> jsonb
--   insertar_evidencia(int, text, text, text, int, text, int) -> jsonb
--
-- Administracion de docentes:
--   sie_admin_listar_docentes(text) -> jsonb
--   sie_admin_crear_docente(text, text, text, text, text, jsonb) -> jsonb
--   sie_admin_actualizar_docente(text, int, text, text, jsonb, boolean, text) -> jsonb
--   sie_docente_listar_estudiantes_salon(text, text, text, text) -> jsonb

-- =============================================================================
-- TRIGGERS EXISTENTES
-- =============================================================================
-- trigger_actualizar_fecha_cita_padre      BEFORE UPDATE ON citas_padres
-- trigger_actualizar_fecha_estudiante      BEFORE UPDATE ON estudiantes
-- trigger_incidencias_calcular_nivel       BEFORE INSERT ON incidencias
-- trg_auditoria_incidencias                AFTER I/U/D ON incidencias
-- trg_auditoria_registros_llegada          AFTER I/U/D ON registros_llegada

-- =============================================================================
-- RLS
-- =============================================================================
-- RLS habilitado en: app_sesiones, usuarios, estudiantes, incidencias,
-- registros_llegada, catalogo_faltas, citas_padres, configuracion_sistema,
-- configuracion_reincidencia, auditoria_logs, comentarios_incidencias,
-- evidencias_fotograficas, tokens_recuperacion, padres_estudiantes.
--
-- Las politicas se apoyan en sie_sesion_rol() / sie_es_staff_sesion(), que leen
-- el header x-sie-token via PostgREST con la anon key.
--
-- IMPLICACION PARA EL CANAL: Django se conecta con un rol de servicio que EVITA
-- estas politicas. El aislamiento del canal apoderado se aplica en la capa de API
-- (SRS 9.2). Este RLS se conserva intacto para el sistema web.

-- Buckets de storage: 'fotos-perfil' y 'evidencias' (ambos publicos).
