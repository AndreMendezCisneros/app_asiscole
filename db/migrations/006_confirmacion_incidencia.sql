-- =============================================================================
-- 006_confirmacion_incidencia.sql — BD CENTRAL
-- Tabla asis_confirmacion_incidencia + flag citacion.
-- Idempotente. Django sigue siendo la fuente de verdad en producción.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.asis_confirmacion_incidencia (
  id                    BIGSERIAL   PRIMARY KEY,
  apoderado_id          BIGINT      NOT NULL REFERENCES public.asis_apoderado(id) ON DELETE CASCADE,
  tenant_id             TEXT        NOT NULL,
  id_incidencia_colegio INTEGER     NOT NULL,
  confirmada_en         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT asis_uniq_conf_incidencia
    UNIQUE (apoderado_id, tenant_id, id_incidencia_colegio)
);

CREATE INDEX IF NOT EXISTS asis_idx_conf_apo_ten
  ON public.asis_confirmacion_incidencia (apoderado_id, tenant_id);

COMMENT ON TABLE public.asis_confirmacion_incidencia IS
  'Confirmacion de lectura de incidencias. No altera tablas del colegio.';

INSERT INTO public.asis_feature_flag (clave, activo, descripcion)
VALUES ('citacion', false, 'Modulo de citacion (stub)')
ON CONFLICT (clave) DO NOTHING;

COMMIT;
