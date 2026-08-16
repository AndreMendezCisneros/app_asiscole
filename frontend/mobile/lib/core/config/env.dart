/// Configuración de entorno de la app.
///
/// Por defecto apunta al VPS de producción (también en debug), porque las
/// pruebas suelen hacerse en celular físico. `10.0.2.2` solo sirve al emulador.
///
/// - Producción (default): `https://jeanpiaget.asiscole.com/canal-api/v0.1`
/// - Emulador + Django local: `--dart-define=ASISCOLE_ENV=dev`
/// - URL explícita: `--dart-define=API_BASE_URL=http://192.168.x.x:8000/v0.1`
///   o `.\run_dispositivo.ps1 -Local`
class Env {
  const Env._();

  static const String _baseUrlDefinida =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static const String _entornoDefinido =
      String.fromEnvironment('ASISCOLE_ENV', defaultValue: '');

  /// Backend del canal en el VPS (Caddy → Django).
  static const String _produccion =
      'https://jeanpiaget.asiscole.com/canal-api/v0.1';

  /// Emulador Android → host local (solo con ASISCOLE_ENV=dev).
  static const String _desarrollo = 'http://10.0.2.2:8000/v0.1';

  /// True salvo que se pida explícitamente `dev` / `development`.
  static bool get esProduccion {
    final e = _entornoDefinido.toLowerCase();
    if (e == 'dev' || e == 'development') return false;
    if (e == 'prod' || e == 'production') return true;
    // Default: VPS (debug en dispositivo físico no alcanza 10.0.2.2).
    return true;
  }

  static String get baseUrl {
    if (_baseUrlDefinida.isNotEmpty) return _baseUrlDefinida;
    return esProduccion ? _produccion : _desarrollo;
  }

  /// Con 20 s/30 s el apoderado se quedaba medio minuto mirando un spinner antes
  /// de que la app pudiera decirle que no había red. El backend responde en
  /// milisegundos incluso bajo carga, así que esperar más no aporta nada.
  static const Duration timeoutConexion = Duration(seconds: 10);
  static const Duration timeoutRespuesta = Duration(seconds: 15);

  /// Zona horaria del colegio. Todas las fechas se muestran en esta zona.
  static const String zonaHoraria = 'America/Lima';

  static const String locale = 'es_PE';

  /// Nombre visible en el launcher, la barra y las notificaciones.
  static const String nombreApp = 'Asis Messenger';

  /// Soporte del canal. Antes de iniciar sesión la app no sabe de qué colegio es
  /// el apoderado, así que el contacto es único y desde ahí se deriva al colegio.
  static const String correoSoporte = 'soporte@asiscole.com';

  /// Página pública con el procedimiento de eliminación de cuenta (Play la exige
  /// además del botón en Perfil).
  static const String urlEliminarCuenta =
      'https://jeanpiaget.asiscole.com/canal-api/eliminar-cuenta';

  /// Ficha de Play. `in_app_update` no funciona en APK de sideload; el botón
  /// de actualizar cae aquí.
  static const String urlFichaPlay =
      'https://play.google.com/store/apps/details?id=pe.asiscole.asiscole_app';

  /// TTL de una solicitud de transferencia de sesión (contrato: 5 minutos).
  static const Duration ttlTransferencia = Duration(minutes: 5);

  /// Intervalo de sondeo del estado de la transferencia.
  static const Duration intervaloSondeoTransferencia = Duration(seconds: 5);
}
