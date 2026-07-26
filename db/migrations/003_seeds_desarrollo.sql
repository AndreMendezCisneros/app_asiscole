-- =============================================================================
-- 003_seeds_desarrollo.sql - DATOS DE PRUEBA. SOLO PARA DESARROLLO LOCAL.
-- =============================================================================
-- ATENCION: NO EJECUTAR EN LA BASE DE DATOS DE UN COLEGIO REAL.
--
-- Se ejecuta sobre una BD DE COLEGIO local (la que ya tiene el esquema legado y,
-- idealmente, el script 001 aplicado). Sirve para probar de punta a punta:
--   * la normalizacion de telefonos a E.164 (los tres formatos peruanos de abajo),
--   * el login por telefono + codigo_barras,
--   * los triggers del outbox (entrada, salida e incidencia).
--
-- Todos los nombres, codigos y telefonos son ficticios.
-- Idempotente: se puede ejecutar varias veces. Como catalogo_faltas y incidencias
-- no tienen una clave natural unica, se usa INSERT ... WHERE NOT EXISTS en vez de
-- ON CONFLICT (no se pueden agregar constraints a tablas legadas).
--
-- Si 001 ya esta aplicado, este script deja filas en public.asis_outbox. Para
-- comprobarlo:  SELECT tipo, id_registro, payload FROM public.asis_outbox;
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Usuario Tutor (quien registra asistencia e incidencias en el colegio)
-- -----------------------------------------------------------------------------
-- La contrasena de desarrollo es "Demo1234", hasheada con bcrypt via pgcrypto,
-- igual que hace el sistema web (extensions.crypt / validar_password).
INSERT INTO public.usuarios (username, password_hash, nombre_completo, email, rol, activo)
VALUES (
  'tutor.demo',
  extensions.crypt('Demo1234', extensions.gen_salt('bf')),
  'Rosa Quispe Mamani',
  'tutor.demo@colegio-demo.edu.pe',
  'Tutor',
  true
)
ON CONFLICT (username) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Estudiantes
-- -----------------------------------------------------------------------------
-- codigo_barras hace de "DNI del estudiante" en el login del canal (RF-A01).
-- Los tres telefonos son el MISMO tipo de numero escrito de tres formas distintas,
-- a proposito, para ejercitar la normalizacion a E.164 (+51XXXXXXXXX):
--   '987654321'        -> 9 digitos, sin prefijo pais
--   '+51 987 654 322'  -> E.164 con espacios
--   '51987654323'      -> con prefijo pais y sin '+'
INSERT INTO public.estudiantes
  (codigo_barras, nombre_completo, grado, seccion, nivel_educativo, telefono_contacto,
   nombre_responsable, parentesco_responsable, activo)
VALUES
  ('71234567', 'Luis Alberto Ramos Torres',   '3', 'A', 'Primaria',   '987654321',
   'Carmen Torres Vega',   'Madre', true),
  ('72345678', 'Maria Fernanda Chavez Rojas', '1', 'B', 'Secundaria', '+51 987 654 322',
   'Jorge Chavez Lopez',   'Padre', true),
  ('73456789', 'Diego Sebastian Flores Nina', '5', 'C', 'Secundaria', '51987654323',
   'Elena Nina Ccama',     'Madre', true)
ON CONFLICT (codigo_barras) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Catalogo de faltas
-- -----------------------------------------------------------------------------
INSERT INTO public.catalogo_faltas
  (nombre_falta, categoria, es_grave, puntos_reincidencia, descripcion, activo, orden_visualizacion)
SELECT 'Uso de celular en clase', 'Disciplina', false, 1,
       'Utilizar el telefono movil durante la sesion de aprendizaje.', true, 10
WHERE NOT EXISTS (
  SELECT 1 FROM public.catalogo_faltas WHERE nombre_falta = 'Uso de celular en clase'
);

INSERT INTO public.catalogo_faltas
  (nombre_falta, categoria, es_grave, puntos_reincidencia, descripcion, activo, orden_visualizacion)
SELECT 'Agresion fisica a un companero', 'Convivencia', true, 3,
       'Agresion fisica hacia otro estudiante dentro del local escolar.', true, 20
WHERE NOT EXISTS (
  SELECT 1 FROM public.catalogo_faltas WHERE nombre_falta = 'Agresion fisica a un companero'
);

-- -----------------------------------------------------------------------------
-- Registros de llegada (dispara asis_trg_llegada_entrada)
-- -----------------------------------------------------------------------------
-- La fecha se calcula en la zona del colegio, no en la del servidor.
INSERT INTO public.registros_llegada
  (id_estudiante, fecha, hora_llegada, estado, registrado_por)
SELECT e.id_estudiante,
       (timezone('America/Lima', now()))::date,
       TIME '07:42',
       'A tiempo',
       (SELECT id_usuario FROM public.usuarios WHERE username = 'tutor.demo')
  FROM public.estudiantes e
 WHERE e.codigo_barras = '71234567'
ON CONFLICT (id_estudiante, fecha) DO NOTHING;

INSERT INTO public.registros_llegada
  (id_estudiante, fecha, hora_llegada, estado, registrado_por)
SELECT e.id_estudiante,
       (timezone('America/Lima', now()))::date,
       TIME '08:15',
       'Tarde',
       (SELECT id_usuario FROM public.usuarios WHERE username = 'tutor.demo')
  FROM public.estudiantes e
 WHERE e.codigo_barras = '72345678'
ON CONFLICT (id_estudiante, fecha) DO NOTHING;

-- Llegada de ayer, para tener mas de un dia en la bandeja.
INSERT INTO public.registros_llegada
  (id_estudiante, fecha, hora_llegada, estado, registrado_por)
SELECT e.id_estudiante,
       (timezone('America/Lima', now()))::date - 1,
       TIME '07:55',
       'A tiempo',
       (SELECT id_usuario FROM public.usuarios WHERE username = 'tutor.demo')
  FROM public.estudiantes e
 WHERE e.codigo_barras = '73456789'
ON CONFLICT (id_estudiante, fecha) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Salida (dispara asis_trg_llegada_salida: NULL -> hora_salida)
-- -----------------------------------------------------------------------------
-- Solo afecta filas sin hora de salida, asi que en una segunda ejecucion no hace
-- nada y no se vuelve a encolar el evento.
UPDATE public.registros_llegada r
   SET hora_salida = TIME '13:05',
       tipo_salida = 'Normal',
       fecha_salida = now(),
       registrado_salida_por = (SELECT id_usuario FROM public.usuarios WHERE username = 'tutor.demo')
  FROM public.estudiantes e
 WHERE e.id_estudiante = r.id_estudiante
   AND e.codigo_barras = '71234567'
   AND r.fecha = (timezone('America/Lima', now()))::date
   AND r.hora_salida IS NULL;

-- El estudiante '72345678' se queda sin hora_salida a proposito: sirve para probar
-- el trigger de salida a mano desde psql o desde el sistema web.

-- -----------------------------------------------------------------------------
-- Incidencia activa (dispara asis_trg_incidencia)
-- -----------------------------------------------------------------------------
INSERT INTO public.incidencias
  (id_estudiante, id_falta, id_usuario_registro, observaciones, estado)
SELECT e.id_estudiante,
       f.id_falta,
       u.id_usuario,
       'Uso del celular durante la clase de Matematica. Se retuvo el equipo.',
       'Activa'
  FROM public.estudiantes e
 CROSS JOIN public.catalogo_faltas f
 CROSS JOIN public.usuarios u
 WHERE e.codigo_barras = '72345678'
   AND f.nombre_falta = 'Uso de celular en clase'
   AND u.username = 'tutor.demo'
   AND NOT EXISTS (
     SELECT 1
       FROM public.incidencias i
      WHERE i.id_estudiante = e.id_estudiante
        AND i.id_falta = f.id_falta
   );

COMMIT;
