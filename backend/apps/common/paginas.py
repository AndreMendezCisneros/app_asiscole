"""Paginas publicas del canal (HTML, sin autenticacion y sin datos personales).

Google Play exige que la eliminacion de cuenta se pueda solicitar tambien desde
una URL web, no solo dentro de la app. Esta pagina cumple ese requisito: explica
el procedimiento y no recibe ni muestra ningun dato del apoderado.
"""

from __future__ import annotations

from django.http import HttpRequest, HttpResponse

CORREO_SOPORTE = "soporte@asiscole.com"
NOMBRE_APP = "Asis Messenger"

_ELIMINAR_CUENTA_HTML = f"""<!DOCTYPE html>
<html lang="es-PE">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Eliminar mi cuenta - {NOMBRE_APP}</title>
<style>
  body {{
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    max-width: 44rem; margin: 0 auto; padding: 2rem 1.25rem;
    line-height: 1.6; color: #1f2430; background: #f7f7fb;
  }}
  h1 {{ color: #5b21e6; font-size: 1.6rem; }}
  h2 {{ font-size: 1.15rem; margin-top: 2rem; }}
  ol, ul {{ padding-left: 1.25rem; }}
  li {{ margin-bottom: .4rem; }}
  .aviso {{
    background: #fff; border-left: 4px solid #5b21e6;
    padding: .9rem 1.1rem; border-radius: .4rem; margin: 1.5rem 0;
  }}
  footer {{ margin-top: 2.5rem; font-size: .9rem; color: #5a6072; }}
  a {{ color: #5b21e6; }}
</style>
</head>
<body>
<h1>Eliminar mi cuenta de {NOMBRE_APP}</h1>

<p>{NOMBRE_APP} es el canal por el que el colegio avisa al apoderado de las
entradas, salidas, incidencias y avisos de su hijo o hija. Puedes eliminar tu
cuenta cuando quieras, desde la propia aplicacion.</p>

<h2>Desde la aplicacion</h2>
<ol>
  <li>Abre {NOMBRE_APP} e inicia sesion.</li>
  <li>Entra en la pestana <strong>Perfil</strong>.</li>
  <li>Pulsa <strong>Eliminar mi cuenta</strong>.</li>
  <li>Confirma con el documento del estudiante.</li>
</ol>

<div class="aviso">
  <strong>La eliminacion no se puede deshacer.</strong> Dejaras de recibir los
  avisos del colegio y, si quieres volver a recibirlos, tendras que registrarte
  de nuevo.
</div>

<h2>Que se elimina</h2>
<ul>
  <li>Tu numero de telefono y tu nombre en el canal se anonimizan.</li>
  <li>Se cierran tus sesiones y se desactivan las notificaciones.</li>
  <li>Los mensajes de tu bandeja se anonimizan: pierden el nombre del estudiante
      y su contenido.</li>
  <li>La copia guardada en el telefono se borra al eliminar la cuenta.</li>
</ul>

<h2>Que no se elimina</h2>
<p>El expediente academico del estudiante (matricula, asistencia, notas)
pertenece al colegio y se conserva segun sus propias normas. Este canal no lo
modifica. Para cualquier gestion sobre esos datos hay que dirigirse al colegio.</p>

<h2>Si no puedes entrar a la aplicacion</h2>
<p>Escribe a <a href="mailto:{CORREO_SOPORTE}">{CORREO_SOPORTE}</a> indicando el
colegio. Por seguridad no pedimos ni tramitamos datos del estudiante por correo:
te derivaremos con la institucion, que es quien verifica la identidad del
apoderado.</p>

<footer>
  Tratamiento de datos conforme a la Ley N.&ordm; 29733 de Proteccion de Datos
  Personales (Peru).
</footer>
</body>
</html>
"""


def eliminar_cuenta(request: HttpRequest) -> HttpResponse:
    """Instrucciones publicas de eliminacion de cuenta (requisito de Play)."""
    return HttpResponse(_ELIMINAR_CUENTA_HTML, content_type="text/html; charset=utf-8")
