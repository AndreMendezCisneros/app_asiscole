"""Paginas publicas del canal (HTML, sin autenticacion y sin datos personales).

Google Play exige una URL de privacidad y que la eliminacion de cuenta se pueda
solicitar tambien desde la web, no solo dentro de la app. Estas paginas cumplen
esos requisitos: no reciben ni muestran ningun dato del apoderado.
"""

from __future__ import annotations

from django.http import HttpRequest, HttpResponse

CORREO_SOPORTE = "trabajoandre4@gmail.com"
NOMBRE_APP = "Asis Messenger"
URL_ELIMINAR = "https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta"
URL_PRIVACIDAD = "https://jeanpiaget.asiscole.com/canal-api/privacidad"

_ESTILOS = """
  body {
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    max-width: 44rem; margin: 0 auto; padding: 2rem 1.25rem;
    line-height: 1.6; color: #1f2430; background: #f7f7fb;
  }
  h1 { color: #5b21e6; font-size: 1.6rem; }
  h2 { font-size: 1.15rem; margin-top: 2rem; }
  ol, ul { padding-left: 1.25rem; }
  li { margin-bottom: .4rem; }
  table { border-collapse: collapse; width: 100%; background: #fff; }
  th, td { border: 1px solid #e2e8f0; padding: .5rem .7rem; text-align: left; }
  th { background: #f1f5f9; }
  .aviso {
    background: #fff; border-left: 4px solid #5b21e6;
    padding: .9rem 1.1rem; border-radius: .4rem; margin: 1.5rem 0;
  }
  footer { margin-top: 2.5rem; font-size: .9rem; color: #5a6072; }
  a { color: #5b21e6; }
"""

_ELIMINAR_CUENTA_HTML = f"""<!DOCTYPE html>
<html lang="es-PE">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Eliminar mi cuenta - {NOMBRE_APP}</title>
<style>{_ESTILOS}</style>
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

<p>Politica de privacidad: <a href="{URL_PRIVACIDAD}">{URL_PRIVACIDAD}</a></p>

<footer>
  Tratamiento de datos conforme a la Ley N.&ordm; 29733 de Proteccion de Datos
  Personales (Peru). Una marca de RYJEC.
</footer>
</body>
</html>
"""

_PRIVACIDAD_HTML = f"""<!DOCTYPE html>
<html lang="es-PE">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Politica de privacidad - {NOMBRE_APP}</title>
<style>{_ESTILOS}</style>
</head>
<body>
<h1>Politica de privacidad de {NOMBRE_APP}</h1>
<p>Ultima actualizacion: 17 de septiembre de 2026.</p>

<p>{NOMBRE_APP} (identificador Android <code>pe.asiscole.asiscole_app</code>) es
el canal movil con el que el colegio avisa al apoderado de entradas, salidas,
incidencias y avisos. Es un producto de <strong>RYJEC / Asiscole</strong>.
Sitio: <a href="https://asiscole.com/es">asiscole.com</a>.</p>

<div class="aviso">
El titular de la cuenta es el <strong>apoderado (adulto)</strong>. No es una
aplicacion infantil. Trata datos vinculados a menores solo para informar al
padre, madre o tutor, conforme a la Ley N.&ordm; 29733.
</div>

<h2>1. Que datos se tratan</h2>
<table>
  <tr><th>Dato</th><th>Para que</th></tr>
  <tr><td>Telefono del apoderado</td><td>Identificar la cuenta e iniciar sesion</td></tr>
  <tr><td>Documento o codigo de barras del estudiante</td>
      <td>Verificar el vinculo en el login. No se guarda en la base central del canal</td></tr>
  <tr><td>Nombre, grado y seccion</td><td>Mostrar al hijo vinculado</td></tr>
  <tr><td>Mensajes generados por el sistema</td><td>Bandeja de avisos</td></tr>
  <tr><td>Token de notificaciones del dispositivo</td><td>Entregar avisos push</td></tr>
  <tr><td>Diagnostico de fallos (Crashlytics)</td>
      <td>Corregir errores. Sin nombres ni telefonos de menores</td></tr>
</table>
<p>No hay publicidad, perfilado comercial ni venta de datos a terceros.</p>

<h2>2. Conservacion</h2>
<p>Los mensajes de la base central se purgan o anonimizan a los <strong>24 meses</strong>
de su emision. La copia en el telefono la borra el apoderado (cerrar sesion,
eliminar cuenta o «Borrar mensajes guardados»). El respaldo de Android esta
desactivado: la cache no llega a Drive.</p>

<h2>3. Derechos (ARCO)</h2>
<ul>
  <li><strong>Acceso:</strong> bandeja y perfil en la app.</li>
  <li><strong>Rectificacion:</strong> a traves del colegio, que corrige el dato en su sistema.</li>
  <li><strong>Cancelacion:</strong> Perfil → Eliminar mi cuenta, o
      <a href="{URL_ELIMINAR}">{URL_ELIMINAR}</a>.</li>
  <li><strong>Oposicion:</strong> cierre de sesion y/o eliminacion de cuenta.</li>
</ul>
<p>La eliminacion anonimiza al apoderado, cierra sesiones y apaga el push. El
expediente academico del estudiante pertenece al colegio y no se borra por esta via.</p>

<h2>4. Seguridad</h2>
<p>Comunicaciones cifradas (HTTPS/TLS). Tokens en el almacen seguro del telefono.
Un login fallido no revela si el fallo fue por telefono o por documento.</p>

<h2>5. Contacto</h2>
<p>Consultas de privacidad o ejercicio de derechos:
<a href="mailto:{CORREO_SOPORTE}">{CORREO_SOPORTE}</a>.
Cuando el colegio tenga un buzon institucional propio, se publicara aqui.</p>

<footer>
  Ley N.&ordm; 29733 de Proteccion de Datos Personales (Peru). RYJEC · Asiscole.
</footer>
</body>
</html>
"""


def eliminar_cuenta(request: HttpRequest) -> HttpResponse:
    """Instrucciones publicas de eliminacion de cuenta (requisito de Play)."""
    return HttpResponse(_ELIMINAR_CUENTA_HTML, content_type="text/html; charset=utf-8")


def privacidad(request: HttpRequest) -> HttpResponse:
    """Politica de privacidad publica (requisito de Play)."""
    return HttpResponse(_PRIVACIDAD_HTML, content_type="text/html; charset=utf-8")
