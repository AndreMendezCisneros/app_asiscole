-- =============================================================================
-- 005_central_gaps.sql — BD CENTRAL
-- Alinea el esquema SQL con lo que ya crean las migraciones de Django:
--   * estudiante activo en asis_apoderado (RF-I03)
--   * asis_cursor_ingesta (poller de outbox)
-- Idempotente. Django sigue siendo la fuente de verdad en producción.
-- =============================================================================

BEGIN;

ALTER TABLE public.asis_apoderado
  ADD COLUMN IF NOT EXISTS estudiante_activo_id INTEGER NULL;

ALTER TABLE public.asis_apoderado
  ADD COLUMN IF NOT EXISTS estudiante_activo_tenant TEXT NULL;

COMMENT ON COLUMN public.asis_apoderado.estudiante_activo_id IS
  'Estudiante activo del apoderado (contexto global de la app, RF-I03).';
COMMENT ON COLUMN public.asis_apoderado.estudiante_activo_tenant IS
  'Colegio del estudiante activo; sale del directorio, nunca del cliente.';

CREATE TABLE IF NOT EXISTS public.asis_cursor_ingesta (
  tenant_id      TEXT        PRIMARY KEY,
  ultimo_id      BIGINT      NOT NULL DEFAULT 0,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.asis_cursor_ingesta IS
  'Ultimo id de asis_outbox procesado por colegio. Vive en la BD central.';

COMMIT;
