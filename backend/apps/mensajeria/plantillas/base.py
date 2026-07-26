"""Contrato de las plantillas de mensaje (patron Strategy).

Todo el texto que ve el apoderado lo produce el backend; anadir un tipo de
mensaje jamas debe obligar a publicar una version nueva de la app. Cada tipo es
una clase con la misma interfaz y se registra en
`apps.mensajeria.plantillas.registry`.

`ContextoEvento` llega con el estudiante, el colegio y los datos del evento ya
resueltos: **la plantilla no consulta la base de datos**. Los campos vienen del
`payload` que el trigger `asis_fn_encolar_evento` deja en `asis_outbox`
(`db/migrations/001_colegio_outbox.sql`), y las horas ya vienen formateadas en la
zona del colegio, asi que aqui no se vuelve a convertir nada.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


class ErrorDePlantilla(Exception):
    """Fallo al construir el texto de un mensaje.

    Se prefiere fallar de forma explicita antes que entregar un mensaje vacio o
    a medias: un aviso mudo en el telefono del apoderado es peor que un evento
    que se reintenta.
    """


class PlantillaNoRegistrada(ErrorDePlantilla):
    """El tipo de mensaje no tiene ninguna plantilla asociada."""


class DatosDeEventoIncompletos(ErrorDePlantilla):
    """El payload del evento no trae lo minimo que la plantilla necesita."""


@dataclass(frozen=True)
class ContextoEvento:
    """Datos ya resueltos que necesita una plantilla.

    Attributes:
        tipo: Tipo de mensaje (`entrada`, `salida`, `incidencia`, `aviso`,
            `personalizado`).
        tenant_id: Colegio del evento.
        colegio: Nombre visible del colegio, para los avisos institucionales.
        id_estudiante: Id del estudiante en su colegio; `None` en los avisos que
            no cuelgan de un estudiante concreto.
        estudiante_nombre: Nombre completo tal como lo guarda el colegio.
        fecha: Fecha del evento, `YYYY-MM-DD`, ya en America/Lima.
        hora: Hora del evento, `HH:MM`, ya en America/Lima.
        estado: Solo en entradas: `A tiempo` o `Tarde`.
        tipo_salida: Solo en salidas: `Normal`, `Autorizada` o `Sin registro`.
        texto_libre: Cuerpo que redacta un administrador (avisos y mensajes
            personalizados).
        extra: Campos del payload que no tienen hueco propio. No se usan para
            redactar, solo viajan en `metadata` para el deep-link.
    """

    tipo: str
    tenant_id: str = ""
    colegio: str = ""
    id_estudiante: int | None = None
    estudiante_nombre: str = ""
    grado: str | None = None
    seccion: str | None = None
    nivel: str | None = None

    fecha: str | None = None
    hora: str | None = None

    # Entrada
    estado: str | None = None

    # Salida
    tipo_salida: str | None = None

    # Incidencia
    id_falta: int | None = None
    nombre_falta: str | None = None
    categoria: str | None = None
    es_grave: bool = False
    nivel_reincidencia: int | None = None
    observaciones: str | None = None
    reportado_por: str | None = None

    # Aviso y personalizado
    texto_libre: str | None = None

    id_registro: int | None = None
    extra: dict = field(default_factory=dict)

    @property
    def es_tardanza(self) -> bool:
        """True si la entrada se registro fuera de hora.

        El colegio guarda el estado como texto (`'A tiempo'` / `'Tarde'`), asi
        que se compara sin distinguir mayusculas ni espacios sobrantes.
        """
        return (self.estado or "").strip().lower() == "tarde"

    @property
    def salida_autorizada(self) -> bool:
        """True si la salida fue autorizada antes de la hora habitual."""
        return (self.tipo_salida or "").strip().lower() == "autorizada"

    def exigir(self, *campos: str) -> None:
        """Comprueba que los campos indicados tengan valor.

        Args:
            *campos: Nombres de atributos obligatorios para esa plantilla.

        Raises:
            DatosDeEventoIncompletos: Si falta alguno. El error solo nombra el
                campo, nunca su valor, porque el valor es dato personal.
        """
        faltantes = [
            nombre
            for nombre in campos
            if getattr(self, nombre, None) in (None, "", [])
        ]
        if faltantes:
            raise DatosDeEventoIncompletos(
                f"faltan campos en el evento {self.tipo}: {', '.join(sorted(faltantes))}"
            )

    def metadata(self) -> dict:
        """Construye el `metadata` del mensaje, para el deep-link de la app.

        Returns:
            Diccionario serializable en JSON. Vive en la BD central, nunca en un
            log, y trae solo lo que la pantalla de detalle necesita.
        """
        datos: dict[str, object] = {
            "tipo": self.tipo,
            "tenant_id": self.tenant_id,
        }
        opcionales = {
            "id_estudiante": self.id_estudiante,
            "estudiante_nombre": self.estudiante_nombre or None,
            "grado": self.grado,
            "seccion": self.seccion,
            "nivel": self.nivel,
            "fecha": self.fecha,
            "hora": self.hora,
            "estado": self.estado,
            "tipo_salida": self.tipo_salida,
            "id_falta": self.id_falta,
            "categoria": self.categoria,
            "es_grave": self.es_grave if self.tipo == "incidencia" else None,
            "nivel_reincidencia": self.nivel_reincidencia,
            "id_registro": self.id_registro,
        }
        datos.update({clave: valor for clave, valor in opcionales.items() if valor is not None})
        return datos

    @classmethod
    def desde_payload(
        cls,
        tipo: str,
        tenant_id: str,
        payload: dict | None,
        *,
        colegio: str = "",
        id_registro: int | None = None,
    ) -> ContextoEvento:
        """Arma el contexto a partir del `payload` de `asis_outbox`.

        Los nombres de campo son exactamente los que escribe el trigger del
        colegio (`001_colegio_outbox.sql`); no se renombra nada por el camino
        para que un cambio en el trigger salte a la vista.

        Args:
            tipo: `entrada`, `salida` o `incidencia`.
            tenant_id: Colegio del que proviene el evento.
            payload: JSON de la fila del outbox.
            colegio: Nombre visible del colegio.
            id_registro: PK de la fila de origen en el colegio.

        Returns:
            El contexto listo para la plantilla.
        """
        datos = dict(payload or {})

        # `hora` unifica las tres formas en que el trigger nombra la hora segun
        # el tipo de evento; asi las plantillas no repiten el mapeo.
        hora = datos.get("hora") or datos.get("hora_llegada") or datos.get("hora_salida")

        conocidos = {
            "tipo",
            "id_estudiante",
            "nombre_completo",
            "grado",
            "seccion",
            "nivel_educativo",
            "fecha",
            "hora",
            "hora_llegada",
            "hora_salida",
            "estado",
            "tipo_salida",
            "id_falta",
            "nombre_falta",
            "categoria",
            "es_grave",
            "nivel_reincidencia",
            "observaciones",
            "id_usuario_registro",
            "nombre_usuario_registro",
            "fecha_hora_registro",
        }

        id_estudiante = datos.get("id_estudiante")
        return cls(
            tipo=tipo,
            tenant_id=tenant_id,
            colegio=colegio,
            id_estudiante=int(id_estudiante) if id_estudiante is not None else None,
            estudiante_nombre=str(datos.get("nombre_completo") or "").strip(),
            grado=datos.get("grado"),
            seccion=datos.get("seccion"),
            nivel=datos.get("nivel_educativo"),
            fecha=datos.get("fecha"),
            hora=hora,
            estado=datos.get("estado"),
            tipo_salida=datos.get("tipo_salida"),
            id_falta=datos.get("id_falta"),
            nombre_falta=datos.get("nombre_falta"),
            categoria=datos.get("categoria"),
            es_grave=bool(datos.get("es_grave")),
            nivel_reincidencia=datos.get("nivel_reincidencia"),
            observaciones=datos.get("observaciones"),
            reportado_por=datos.get("nombre_usuario_registro"),
            id_registro=id_registro,
            extra={clave: valor for clave, valor in datos.items() if clave not in conocidos},
        )


class PlantillaBase(ABC):
    """Interfaz comun de todas las plantillas.

    Una plantilla es pura: recibe el contexto y devuelve texto. No toca la BD,
    no envia nada y no depende de la peticion en curso.
    """

    #: Tipo de mensaje que sabe redactar. Es la clave del registro.
    tipo: str = ""

    @abstractmethod
    def render(self, ctx: ContextoEvento) -> str:
        """Devuelve el texto final del mensaje.

        Args:
            ctx: Datos del evento ya resueltos.

        Returns:
            Una o dos frases en espanol de Peru, sin emojis, pensadas para
            leerse en una notificacion.

        Raises:
            DatosDeEventoIncompletos: Si el evento no trae lo indispensable.
        """
