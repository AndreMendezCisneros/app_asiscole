-- =============================================================================
-- 008_central_app_version.sql — SE EJECUTA EN LA BD CENTRAL DEL CANAL
-- =============================================================================
-- Politica de versiones de la app (Fase 7 de QA). Permite cortar una version con
-- un fallo grave sin esperar a que el apoderado abra la tienda.
--
-- Django tambien crea esta tabla con `manage.py migrate` (administracion 0002).
-- Este script existe para el mismo caso que 002/007: dejar la central lista y
-- con RLS activo aunque se toque desde SQL. Es idempotente.
--
-- Semilla deliberada: min_soportada = 1. Subir ese numero deja fuera a todos los
-- APK anteriores, asi que tiene que ser una decision consciente, nunca un efecto
-- colateral del despliegue.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.asis_app_version (
  id                BIGSERIAL   PRIMARY KEY,
  plataforma        text        NOT NULL UNIQUE,
  min_soportada     integer     NOT NULL DEFAULT 1 CHECK (min_soportada >= 1),
  ultima_disponible integer     NOT NULL DEFAULT 1 CHECK (ultima_disponible >= 1),
  mensaje           text,
  url_tienda        text,
  actualizado_en    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT asis_app_version_min_coherente CHECK (min_soportada <= ultima_disponible)
);

INSERT INTO public.asis_app_version (plataforma, min_soportada, ultima_disponible, url_tienda, mensaje)
VALUES (
  'android',
  1,
  2,
  'https://play.google.com/store/apps/details?id=pe.asiscole.asiscole_app',
  'Hay una versión nueva de Asis Messenger.'
)
ON CONFLICT (plataforma) DO NOTHING;

-- La central suele vivir en Supabase: sin RLS, el rol anon podria escribir aqui
-- y bloquear a todos los apoderados de golpe. Django usa un rol BYPASSRLS.
ALTER TABLE public.asis_app_version ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON public.asis_app_version FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON public.asis_app_version FROM authenticated;
  END IF;
END;
$$;

COMMIT;
