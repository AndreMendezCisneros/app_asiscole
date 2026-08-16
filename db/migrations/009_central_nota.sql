-- =============================================================================
-- 009_central_nota.sql — SE EJECUTA EN LA BD CENTRAL DEL CANAL
-- =============================================================================
-- Historial de notas semanales que el SIE empuja con POST /ingesta/eventos
-- (tipo: nota). Django también crea esta tabla con `manage.py migrate`
-- (mensajeria 0002). Este script deja la central lista y con RLS aunque se
-- toque desde SQL. Es idempotente.
--
-- No sustituye al ingest: el SIE no llama a sie_notas_por_estudiante. Esa RPC
-- vive en la BD del colegio y, si se usa, sería para hidratar; el canal de
-- producción llena asis_nota al vuelo.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.asis_nota (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        text        NOT NULL,
  id_estudiante    integer     NOT NULL,
  id_registro      integer     NOT NULL,
  semana_codigo    text,
  semana_etiqueta  text,
  fecha_inicio     date,
  fecha_fin        date,
  nota             text        NOT NULL,
  nota_maxima      text,
  area_codigo      text,
  area_nombre      text,
  carrera          text,
  registrado_en    timestamptz,
  emitido_en       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT asis_uniq_nota_origen UNIQUE (tenant_id, id_estudiante, id_registro)
);

CREATE INDEX IF NOT EXISTS asis_idx_nota_estudiante
  ON public.asis_nota (tenant_id, id_estudiante, fecha_inicio DESC);

ALTER TABLE public.asis_nota ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON public.asis_nota FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON public.asis_nota FROM authenticated;
  END IF;
END;
$$;

COMMIT;
