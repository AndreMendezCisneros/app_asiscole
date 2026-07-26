"""Espejo ORM de las tablas reales de cada colegio (SOLO LECTURA).

Estos modelos mapean el esquema descrito en `db/legacy/bootstrap_colegio.sql`.
Reglas que no se negocian:

* Todos son `managed = False`: Django no las crea, no las altera y no las migra.
  El router (`config.db_router.TenantRouter`) ademas bloquea cualquier migracion
  de esta app y de los alias `colegio_*`.
* El canal NUNCA escribe aqui. Se consultan siempre con
  `.using(tenant_alias(tenant_id))`, y ese `tenant_id` sale del directorio, no
  del cliente.
* Los enums de PostgreSQL (`rol_usuario`, `nivel_educativo`, `estado_incidencia`,
  `estado_evidencia`) se mapean como texto: el canal solo los lee.
* `__str__` devuelve identificadores, nunca nombres ni telefonos, para que un
  repr accidental no acabe escribiendo datos de un menor en un log.
"""

from __future__ import annotations

from django.db import models


class UsuarioColegio(models.Model):
    """Fila de `usuarios`. El apoderado del canal es el que tiene `rol = 'Padre'`.

    `password_hash` y `tokens_recuperacion` se omiten a proposito: el canal tiene
    su propio login y no necesita —ni debe— leer las credenciales del sistema web.
    """

    id_usuario = models.AutoField(primary_key=True, db_column="id_usuario")
    username = models.CharField(max_length=50, db_column="username")
    nombre_completo = models.CharField(max_length=255, db_column="nombre_completo")
    email = models.CharField(max_length=255, db_column="email")
    rol = models.CharField(max_length=20, db_column="rol")
    grados_asignados = models.JSONField(null=True, blank=True, db_column="grados_asignados")
    activo = models.BooleanField(db_column="activo")
    cambio_password_obligatorio = models.BooleanField(db_column="cambio_password_obligatorio")
    ultimo_acceso = models.DateTimeField(null=True, blank=True, db_column="ultimo_acceso")
    intentos_fallidos = models.IntegerField(db_column="intentos_fallidos")
    bloqueado_hasta = models.DateTimeField(null=True, blank=True, db_column="bloqueado_hasta")
    fecha_creacion = models.DateTimeField(db_column="fecha_creacion")

    class Meta:
        managed = False
        db_table = "usuarios"
        verbose_name = "Usuario del colegio"
        verbose_name_plural = "Usuarios del colegio"

    def __str__(self) -> str:
        return f"usuario:{self.pk}"


class Estudiante(models.Model):
    """Fila de `estudiantes`.

    Dos columnas son la clave del canal:

    * `codigo_barras` es el "DNI del estudiante" del login (RF-A01).
    * `telefono_contacto` es el telefono del apoderado, en texto libre; se
      normaliza a E.164 con `apps.common.phone.normalizar_e164`.
    """

    id_estudiante = models.AutoField(primary_key=True, db_column="id_estudiante")
    codigo_barras = models.CharField(max_length=50, unique=True, db_column="codigo_barras")
    nombre_completo = models.CharField(max_length=255, db_column="nombre_completo")
    grado = models.CharField(max_length=20, db_column="grado")
    seccion = models.CharField(max_length=10, db_column="seccion")
    nivel_educativo = models.CharField(max_length=20, db_column="nivel_educativo")
    foto_perfil = models.TextField(null=True, blank=True, db_column="foto_perfil")
    activo = models.BooleanField(db_column="activo")
    telefono_contacto = models.CharField(max_length=20, null=True, blank=True, db_column="telefono_contacto")
    email_contacto = models.CharField(max_length=255, null=True, blank=True, db_column="email_contacto")
    nombre_responsable = models.CharField(max_length=255, null=True, blank=True, db_column="nombre_responsable")
    parentesco_responsable = models.CharField(
        max_length=50, null=True, blank=True, db_column="parentesco_responsable"
    )
    telefono_emergencia = models.CharField(max_length=20, null=True, blank=True, db_column="telefono_emergencia")
    fecha_creacion = models.DateTimeField(db_column="fecha_creacion")
    fecha_actualizacion = models.DateTimeField(db_column="fecha_actualizacion")

    class Meta:
        managed = False
        db_table = "estudiantes"
        verbose_name = "Estudiante"
        verbose_name_plural = "Estudiantes"

    def __str__(self) -> str:
        return f"estudiante:{self.pk}"


class PadreEstudiante(models.Model):
    """Fila de `padres_estudiantes`: el vinculo apoderado-estudiante ya existente.

    Es la fuente de verdad de que estudiantes puede ver un apoderado. Nunca se
    confia en un `estudiante_id` que llegue del cliente sin contrastarlo aqui.
    """

    id_relacion = models.AutoField(primary_key=True, db_column="id_relacion")
    usuario = models.ForeignKey(
        UsuarioColegio,
        on_delete=models.DO_NOTHING,
        db_column="id_usuario",
        related_name="vinculos_estudiantes",
    )
    estudiante = models.ForeignKey(
        Estudiante,
        on_delete=models.DO_NOTHING,
        db_column="id_estudiante",
        related_name="vinculos_apoderados",
    )
    parentesco = models.CharField(max_length=50, null=True, blank=True, db_column="parentesco")
    es_principal = models.BooleanField(null=True, db_column="es_principal")
    fecha_creacion = models.DateTimeField(null=True, blank=True, db_column="fecha_creacion")

    class Meta:
        managed = False
        db_table = "padres_estudiantes"
        unique_together = (("usuario", "estudiante"),)
        verbose_name = "Vinculo apoderado-estudiante"
        verbose_name_plural = "Vinculos apoderado-estudiante"

    def __str__(self) -> str:
        return f"vinculo:{self.pk}"


class RegistroLlegada(models.Model):
    """Fila de `registros_llegada`: la asistencia diaria.

    Ojo con la semantica real del sistema escolar:

    * La ENTRADA es un INSERT (con `hora_llegada` y `estado`).
    * La SALIDA es un UPDATE de `hora_salida` sobre la misma fila.
    * No existen filas para "Falta" ni "Sin registro": se derivan por ausencia
      de fila para esa fecha.
    """

    id_registro = models.AutoField(primary_key=True, db_column="id_registro")
    estudiante = models.ForeignKey(
        Estudiante,
        on_delete=models.DO_NOTHING,
        db_column="id_estudiante",
        related_name="registros_llegada",
    )
    fecha = models.DateField(db_column="fecha")
    hora_llegada = models.TimeField(db_column="hora_llegada")
    estado = models.CharField(max_length=20, db_column="estado")
    registrado_por = models.ForeignKey(
        UsuarioColegio,
        on_delete=models.DO_NOTHING,
        null=True,
        blank=True,
        db_column="registrado_por",
        related_name="llegadas_registradas",
    )
    fecha_creacion = models.DateTimeField(db_column="fecha_creacion")
    hora_salida = models.TimeField(null=True, blank=True, db_column="hora_salida")
    registrado_salida_por = models.ForeignKey(
        UsuarioColegio,
        on_delete=models.DO_NOTHING,
        null=True,
        blank=True,
        db_column="registrado_salida_por",
        related_name="salidas_registradas",
    )
    fecha_salida = models.DateTimeField(null=True, blank=True, db_column="fecha_salida")
    tipo_salida = models.CharField(max_length=20, null=True, blank=True, db_column="tipo_salida")

    class Meta:
        managed = False
        db_table = "registros_llegada"
        unique_together = (("estudiante", "fecha"),)
        verbose_name = "Registro de llegada"
        verbose_name_plural = "Registros de llegada"

    def __str__(self) -> str:
        return f"registro_llegada:{self.pk}"


class CatalogoFalta(models.Model):
    """Fila de `catalogo_faltas`: el tipo de falta que origina una incidencia."""

    id_falta = models.AutoField(primary_key=True, db_column="id_falta")
    nombre_falta = models.CharField(max_length=255, db_column="nombre_falta")
    categoria = models.TextField(db_column="categoria")
    es_grave = models.BooleanField(db_column="es_grave")
    puntos_reincidencia = models.IntegerField(db_column="puntos_reincidencia")
    descripcion = models.TextField(null=True, blank=True, db_column="descripcion")
    activo = models.BooleanField(db_column="activo")
    orden_visualizacion = models.IntegerField(db_column="orden_visualizacion")
    fecha_creacion = models.DateTimeField(db_column="fecha_creacion")

    class Meta:
        managed = False
        db_table = "catalogo_faltas"
        verbose_name = "Falta del catalogo"
        verbose_name_plural = "Catalogo de faltas"

    def __str__(self) -> str:
        return f"falta:{self.pk}"


class Incidencia(models.Model):
    """Fila de `incidencias`.

    `nivel_reincidencia` lo calcula un trigger BEFORE INSERT del colegio; el
    canal solo lo lee. Las incidencias con `estado = 'Anulada'` no se notifican.
    """

    id_incidencia = models.AutoField(primary_key=True, db_column="id_incidencia")
    estudiante = models.ForeignKey(
        Estudiante,
        on_delete=models.DO_NOTHING,
        db_column="id_estudiante",
        related_name="incidencias",
    )
    falta = models.ForeignKey(
        CatalogoFalta,
        on_delete=models.DO_NOTHING,
        db_column="id_falta",
        related_name="incidencias",
    )
    fecha_hora_registro = models.DateTimeField(db_column="fecha_hora_registro")
    usuario_registro = models.ForeignKey(
        UsuarioColegio,
        on_delete=models.DO_NOTHING,
        db_column="id_usuario_registro",
        related_name="incidencias_registradas",
    )
    nivel_reincidencia = models.IntegerField(db_column="nivel_reincidencia")
    observaciones = models.TextField(null=True, blank=True, db_column="observaciones")
    estado_evidencia = models.CharField(max_length=20, db_column="estado_evidencia")
    cantidad_fotos = models.IntegerField(db_column="cantidad_fotos")
    usuario_carga_foto = models.ForeignKey(
        UsuarioColegio,
        on_delete=models.DO_NOTHING,
        null=True,
        blank=True,
        db_column="id_usuario_carga_foto",
        related_name="incidencias_con_foto_cargada",
    )
    fecha_hora_carga_foto = models.DateTimeField(null=True, blank=True, db_column="fecha_hora_carga_foto")
    estado = models.CharField(max_length=20, db_column="estado")
    motivo_anulacion = models.TextField(null=True, blank=True, db_column="motivo_anulacion")
    usuario_anulacion = models.ForeignKey(
        UsuarioColegio,
        on_delete=models.DO_NOTHING,
        null=True,
        blank=True,
        db_column="id_usuario_anulacion",
        related_name="incidencias_anuladas",
    )
    fecha_anulacion = models.DateTimeField(null=True, blank=True, db_column="fecha_anulacion")
    veces_impreso = models.IntegerField(db_column="veces_impreso")
    fecha_ultima_impresion = models.DateTimeField(null=True, blank=True, db_column="fecha_ultima_impresion")

    class Meta:
        managed = False
        db_table = "incidencias"
        verbose_name = "Incidencia"
        verbose_name_plural = "Incidencias"

    def __str__(self) -> str:
        return f"incidencia:{self.pk}"


class EvidenciaFotografica(models.Model):
    """Fila de `evidencias_fotograficas`: fotos adjuntas a una incidencia.

    Los archivos viven en el bucket publico `evidencias` de Supabase. El canal
    solo expone la referencia al apoderado dueno de la incidencia.
    """

    id_evidencia = models.AutoField(primary_key=True, db_column="id_evidencia")
    incidencia = models.ForeignKey(
        Incidencia,
        on_delete=models.DO_NOTHING,
        db_column="id_incidencia",
        related_name="evidencias",
    )
    ruta_archivo = models.TextField(db_column="ruta_archivo")
    nombre_original = models.TextField(db_column="nombre_original")
    nombre_archivo = models.TextField(db_column="nombre_archivo")
    tamano_bytes = models.IntegerField(db_column="tamano_bytes")
    tipo_mime = models.CharField(max_length=100, db_column="tipo_mime")
    usuario_subida = models.ForeignKey(
        UsuarioColegio,
        on_delete=models.DO_NOTHING,
        db_column="id_usuario_subida",
        related_name="evidencias_subidas",
    )
    fecha_subida = models.DateTimeField(db_column="fecha_subida")
    ip_subida = models.CharField(max_length=50, null=True, blank=True, db_column="ip_subida")
    marca_agua_aplicada = models.BooleanField(db_column="marca_agua_aplicada")

    class Meta:
        managed = False
        db_table = "evidencias_fotograficas"
        verbose_name = "Evidencia fotografica"
        verbose_name_plural = "Evidencias fotograficas"

    def __str__(self) -> str:
        return f"evidencia:{self.pk}"
