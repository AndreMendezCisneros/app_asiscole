-- Corrige la idempotencia de asis_mensaje: un evento notifica a CADA apoderado
-- vinculado, no solo al primero. Se ejecuta en la BD central.
BEGIN;
DROP INDEX IF EXISTS public.asis_uniq_mensaje_origen;
CREATE UNIQUE INDEX IF NOT EXISTS asis_uniq_mensaje_origen
  ON public.asis_mensaje (apoderado_id, tenant_id, origen_evento)
  WHERE origen_evento IS NOT NULL;
COMMIT;
