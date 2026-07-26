-- =============================================================================
-- 001_colegio_outbox.sql - SE EJECUTA EN CADA BASE DE DATOS DE COLEGIO
-- =============================================================================
-- Objetivo: que el backend Django del canal apoderado se entere de los eventos
-- nuevos del colegio (entradas, salidas e incidencias) sin acoplarse al esquema
-- legado ni depender de webhooks de Supabase.
--
-- Patron: transactional outbox. Los triggers AFTER del colegio escriben una fila
-- en public.asis_outbox y un poller de Django la consume y la marca procesada.
--
-- REGLAS QUE ESTE SCRIPT RESPETA (.cursor/rules/db-sql.mdc):
--   * Solo cambios aditivos. Cero ALTER/DROP sobre tablas legadas.
--   * Todo objeto nuevo lleva prefijo asis_.
--   * Idempotente: se puede ejecutar dos veces sin fallar.
--   * Los triggers son AFTER y NUNCA abortan la operacion original del colegio.
--   * Zona horaria America/Lima para todo dato de calendario.
--
-- Ejecutar una vez por cada colegio nuevo que se incorpora al canal.
-- Requiere un rol con permisos DDL sobre public (postgres / owner del esquema).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Tabla de outbox
-- -----------------------------------------------------------------------------
-- id_registro guarda la PK de la fila de origen:
--   * 'entrada'    -> registros_llegada.id_registro
--   * 'salida'     -> registros_llegada.id_registro
--   * 'incidencia' -> incidencias.id_incidencia
-- El UNIQUE (tipo, id_registro) es la garantia de idempotencia: un mismo evento
-- jamas se encola dos veces. Entrada y salida comparten id_registro pero se
-- distinguen por tipo, por eso la clave es compuesta.
CREATE TABLE IF NOT EXISTS public.asis_outbox (
  id            BIGSERIAL   PRIMARY KEY,
  tipo          TEXT        NOT NULL CHECK (tipo IN ('entrada', 'salida', 'incidencia')),
  id_estudiante INTEGER     NOT NULL,
  id_registro   INTEGER     NOT NULL,
  payload       JSONB       NOT NULL DEFAULT '{}'::jsonb,
  procesado     BOOLEAN     NOT NULL DEFAULT false,
  intentos      INTEGER     NOT NULL DEFAULT 0,
  ultimo_error  TEXT        NULL,
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  procesado_en  TIMESTAMPTZ NULL,
  CONSTRAINT asis_outbox_evento_unico UNIQUE (tipo, id_registro)
);

COMMENT ON TABLE public.asis_outbox IS
  'Cola de eventos del colegio hacia el canal apoderado (Asiscole). La escribe un '
  'trigger AFTER y la consume el poller de Django con un rol de servicio.';
COMMENT ON COLUMN public.asis_outbox.id_registro IS
  'PK de la fila de origen: registros_llegada.id_registro o incidencias.id_incidencia.';
COMMENT ON COLUMN public.asis_outbox.payload IS
  'Datos ya resueltos que la plantilla del mensaje necesita, para que Django no '
  'tenga que volver a consultar el esquema del colegio.';
COMMENT ON COLUMN public.asis_outbox.ultimo_error IS
  'Diagnostico del poller. Nunca debe contener datos personales del estudiante.';

-- Indice parcial: el poller solo mira lo pendiente, ordenado por antiguedad.
-- Al marcar procesado = true la fila sale del indice y el poller sigue barato.
CREATE INDEX IF NOT EXISTS asis_idx_outbox_pendientes
  ON public.asis_outbox (creado_en)
  WHERE procesado = false;

-- -----------------------------------------------------------------------------
-- 2. Funcion generica de encolado
-- -----------------------------------------------------------------------------
-- Un solo cuerpo para los tres triggers. El tipo de evento llega en TG_ARGV[0].
--
-- SEGURIDAD DEL COLEGIO (no negociable): esta funcion no puede hacer fallar el
-- registro de asistencia ni la incidencia. Todo el trabajo va dentro de un bloque
-- BEGIN ... EXCEPTION WHEN OTHERS, que en PL/pgSQL abre una subtransaccion: si el
-- encolado revienta, solo se revierte el encolado. Siempre RETURN NULL porque es
-- un trigger AFTER y su valor de retorno se ignora.
--
-- SECURITY DEFINER: registros_llegada, incidencias, estudiantes, catalogo_faltas y
-- usuarios tienen RLS activo. Si la funcion corriera con los permisos del invocante
-- (por ejemplo un Tutor via PostgREST), los JOIN podrian devolver cero filas y el
-- payload saldria incompleto. Al ejecutarse como el owner del esquema se lee
-- siempre el dato real. search_path fijo para evitar secuestro de nombres.
--
-- MINIMIZACION (Ley N.o 29733): el payload NO incluye telefono_contacto ni
-- codigo_barras. Django ya resuelve el destinatario con (tenant, id_estudiante)
-- contra su directorio central; propagar identificadores del menor por la cola
-- seria dato personal de mas.
CREATE OR REPLACE FUNCTION public.asis_fn_encolar_evento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $asis_fn_encolar_evento$
DECLARE
  v_tipo        TEXT := TG_ARGV[0];
  v_id_registro INTEGER;
  v_payload     JSONB;
  v_estudiante  RECORD;
  v_falta       RECORD;
  v_reportante  TEXT;
BEGIN
  BEGIN
    -- Datos del estudiante comunes a los tres tipos de evento.
    SELECT e.nombre_completo,
           e.grado,
           e.seccion,
           e.nivel_educativo::text AS nivel_educativo
      INTO v_estudiante
      FROM public.estudiantes e
     WHERE e.id_estudiante = NEW.id_estudiante;

    v_payload := jsonb_build_object(
      'tipo',            v_tipo,
      'id_estudiante',   NEW.id_estudiante,
      'nombre_completo', v_estudiante.nombre_completo,
      'grado',           v_estudiante.grado,
      'seccion',         v_estudiante.seccion,
      'nivel_educativo', v_estudiante.nivel_educativo
    );

    IF v_tipo = 'entrada' THEN
      v_id_registro := NEW.id_registro;
      -- fecha + hora da un timestamp: se formatea sin depender de casts implicitos.
      v_payload := v_payload || jsonb_build_object(
        'fecha',        to_char(NEW.fecha, 'YYYY-MM-DD'),
        'hora_llegada', to_char(NEW.fecha + NEW.hora_llegada, 'HH24:MI'),
        'estado',       NEW.estado  -- 'A tiempo' | 'Tarde'
      );

    ELSIF v_tipo = 'salida' THEN
      v_id_registro := NEW.id_registro;
      v_payload := v_payload || jsonb_build_object(
        'fecha',       to_char(NEW.fecha, 'YYYY-MM-DD'),
        'hora_salida', to_char(NEW.fecha + NEW.hora_salida, 'HH24:MI'),
        'tipo_salida', NEW.tipo_salida  -- 'Normal' | 'Autorizada' | 'Sin registro'
      );

    ELSIF v_tipo = 'incidencia' THEN
      v_id_registro := NEW.id_incidencia;

      SELECT f.nombre_falta,
             f.categoria,
             f.es_grave
        INTO v_falta
        FROM public.catalogo_faltas f
       WHERE f.id_falta = NEW.id_falta;

      -- RF-G04: el apoderado debe saber quien reporto la incidencia.
      SELECT u.nombre_completo
        INTO v_reportante
        FROM public.usuarios u
       WHERE u.id_usuario = NEW.id_usuario_registro;

      v_payload := v_payload || jsonb_build_object(
        'fecha_hora_registro',  NEW.fecha_hora_registro,
        -- Fecha y hora ya convertidas a la zona del colegio, listas para la plantilla.
        'fecha',                to_char(timezone('America/Lima', NEW.fecha_hora_registro), 'YYYY-MM-DD'),
        'hora',                 to_char(timezone('America/Lima', NEW.fecha_hora_registro), 'HH24:MI'),
        'id_falta',             NEW.id_falta,
        'nombre_falta',         v_falta.nombre_falta,
        'categoria',            v_falta.categoria,
        'es_grave',             v_falta.es_grave,
        'nivel_reincidencia',   NEW.nivel_reincidencia,
        'observaciones',        NEW.observaciones,
        'id_usuario_registro',  NEW.id_usuario_registro,
        'nombre_usuario_registro', v_reportante
      );

    ELSE
      -- Trigger mal configurado: no se encola nada, pero la operacion del colegio sigue.
      RETURN NULL;
    END IF;

    INSERT INTO public.asis_outbox (tipo, id_estudiante, id_registro, payload)
    VALUES (v_tipo, NEW.id_estudiante, v_id_registro, v_payload)
    ON CONFLICT (tipo, id_registro) DO NOTHING;

  EXCEPTION WHEN OTHERS THEN
    -- Se traga cualquier error: la asistencia o la incidencia del colegio manda.
    -- Solo se deja rastro tecnico (tipo de evento y SQLSTATE). Prohibido volcar
    -- nombres, telefonos o codigo_barras al log del servidor.
    RAISE WARNING 'asis_outbox: no se pudo encolar el evento % (SQLSTATE %)', v_tipo, SQLSTATE;
    RETURN NULL;
  END;

  RETURN NULL;  -- trigger AFTER: el valor de retorno se ignora.
END;
$asis_fn_encolar_evento$;

COMMENT ON FUNCTION public.asis_fn_encolar_evento() IS
  'Trigger AFTER generico que encola eventos en asis_outbox. El tipo llega en '
  'TG_ARGV[0]. Nunca aborta la operacion original del colegio.';

-- -----------------------------------------------------------------------------
-- 3. Triggers sobre las tablas legadas (solo se agregan, no se tocan los existentes)
-- -----------------------------------------------------------------------------
-- La entrada es un INSERT en registros_llegada.
DROP TRIGGER IF EXISTS asis_trg_llegada_entrada ON public.registros_llegada;
CREATE TRIGGER asis_trg_llegada_entrada
  AFTER INSERT ON public.registros_llegada
  FOR EACH ROW
  EXECUTE FUNCTION public.asis_fn_encolar_evento('entrada');

-- La salida es un UPDATE que rellena hora_salida. Solo interesa la transicion
-- NULL -> valor; correcciones posteriores de la hora no generan un aviso nuevo.
DROP TRIGGER IF EXISTS asis_trg_llegada_salida ON public.registros_llegada;
CREATE TRIGGER asis_trg_llegada_salida
  AFTER UPDATE ON public.registros_llegada
  FOR EACH ROW
  WHEN (OLD.hora_salida IS NULL AND NEW.hora_salida IS NOT NULL)
  EXECUTE FUNCTION public.asis_fn_encolar_evento('salida');

-- Solo se avisa de incidencias vigentes. Las anuladas o en revision no se encolan;
-- una incidencia anulada despues de encolarse la resuelve el backend, no este trigger.
DROP TRIGGER IF EXISTS asis_trg_incidencia ON public.incidencias;
CREATE TRIGGER asis_trg_incidencia
  AFTER INSERT ON public.incidencias
  FOR EACH ROW
  WHEN (NEW.estado = 'Activa')
  EXECUTE FUNCTION public.asis_fn_encolar_evento('incidencia');

-- -----------------------------------------------------------------------------
-- 4. Indice funcional para el login por telefono (RF-A01)
-- -----------------------------------------------------------------------------
-- telefono_contacto es texto libre ('987654321', '+51 987 654 322', '51987...').
-- El login normaliza a digitos y compara; el indice debe usar exactamente la misma
-- expresion para que el planner lo aproveche.
CREATE INDEX IF NOT EXISTS asis_idx_estudiantes_tel_norm
  ON public.estudiantes ((regexp_replace(telefono_contacto, '\D', '', 'g')))
  WHERE telefono_contacto IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 5. Vista origen del directorio central
-- -----------------------------------------------------------------------------
-- Django la lee periodicamente para construir/refrescar asis_directorio en la BD
-- central. Devuelve el telefono tal cual y ya normalizado a digitos, para que la
-- conversion a E.164 (+51...) se resuelva en el backend con reglas de Peru.
--
-- security_invoker = true: la vista no presta privilegios del owner; quien consulta
-- ve lo que sus permisos le permiten. El rol de servicio de Django evita RLS, asi
-- que ve todo. Requiere PostgreSQL 15+ (version de Supabase).
CREATE OR REPLACE VIEW public.asis_v_directorio_origen
WITH (security_invoker = true) AS
SELECT e.id_estudiante,
       e.codigo_barras,
       e.nombre_completo,
       e.grado,
       e.seccion,
       e.nivel_educativo,
       e.telefono_contacto,
       regexp_replace(e.telefono_contacto, '\D', '', 'g') AS telefono_digitos,
       e.activo
  FROM public.estudiantes e
 WHERE e.telefono_contacto IS NOT NULL;

COMMENT ON VIEW public.asis_v_directorio_origen IS
  'Origen del directorio del canal apoderado: estudiantes con telefono de contacto '
  'y su version normalizada a digitos. Consumida por el rol de servicio de Django.';

-- -----------------------------------------------------------------------------
-- 6. Permisos
-- -----------------------------------------------------------------------------
-- No se otorga NADA nuevo a anon ni a authenticated: el canal no se expone por
-- PostgREST. El poller de Django se conecta con un rol de servicio propio, que ya
-- tiene acceso al esquema y evita RLS, asi que no necesita GRANT adicional.
--
-- Ademas se revoca explicitamente el acceso de anon/authenticated sobre los objetos
-- nuevos, porque en Supabase los privilegios por defecto del esquema public pueden
-- otorgarselos de forma automatica al crear la tabla. Revocar sobre objetos propios
-- no altera ningun GRANT del esquema legado.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON public.asis_outbox FROM anon;
    REVOKE ALL ON public.asis_v_directorio_origen FROM anon;
    REVOKE ALL ON SEQUENCE public.asis_outbox_id_seq FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON public.asis_outbox FROM authenticated;
    REVOKE ALL ON public.asis_v_directorio_origen FROM authenticated;
    REVOKE ALL ON SEQUENCE public.asis_outbox_id_seq FROM authenticated;
  END IF;
END;
$$;

-- RLS activo y sin politicas sobre la cola: nadie que pase por PostgREST la ve.
-- El rol de servicio de Django tiene BYPASSRLS y sigue trabajando con normalidad.
-- Esto no modifica el RLS de ninguna tabla legada.
ALTER TABLE public.asis_outbox ENABLE ROW LEVEL SECURITY;

COMMIT;
