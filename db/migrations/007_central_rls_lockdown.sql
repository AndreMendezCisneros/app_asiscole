-- =============================================================================
-- 007_central_rls_lockdown.sql — SE EJECUTA EN LA BD CENTRAL DEL CANAL
-- =============================================================================
-- La central suele vivir en Supabase. Sin RLS, PostgREST/anon podría leer PII.
-- Este script:
--   1) Activa RLS en tablas asis_* sin políticas (deny-all vía PostgREST).
--   2) Revoca privilegios a anon/authenticated si existen.
-- Django se conecta con un rol de servicio (BYPASSRLS) y no se ve afectado.
-- Idempotente.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  t text;
  tablas text[] := ARRAY[
    'asis_apoderado',
    'asis_directorio',
    'asis_sesion_activa',
    'asis_transferencia_sesion',
    'asis_push_token',
    'asis_mensaje',
    'asis_intento_login',
    'asis_feature_flag',
    'asis_auditoria',
    'asis_cursor_ingesta',
    'asis_confirmacion_incidencia'
  ];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = t
    ) THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      -- Sin políticas: nadie sujeto a RLS puede leer/escribir.
    END IF;
  END LOOP;
END;
$$;

DO $$
DECLARE
  t text;
  tablas text[] := ARRAY[
    'asis_apoderado',
    'asis_directorio',
    'asis_sesion_activa',
    'asis_transferencia_sesion',
    'asis_push_token',
    'asis_mensaje',
    'asis_intento_login',
    'asis_feature_flag',
    'asis_auditoria',
    'asis_cursor_ingesta',
    'asis_confirmacion_incidencia'
  ];
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    FOREACH t IN ARRAY tablas LOOP
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = t
      ) THEN
        EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
      END IF;
    END LOOP;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    FOREACH t IN ARRAY tablas LOOP
      IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = t
      ) THEN
        EXECUTE format('REVOKE ALL ON public.%I FROM authenticated', t);
      END IF;
    END LOOP;
  END IF;
END;
$$;

-- Índice para ingesta: lookup por (tenant_id, id_estudiante).
CREATE INDEX IF NOT EXISTS asis_idx_dir_tenant_est
  ON public.asis_directorio (tenant_id, id_estudiante);

COMMIT;
