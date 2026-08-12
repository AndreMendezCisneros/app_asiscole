import 'package:flutter/foundation.dart';

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

  static const Duration timeoutConexion = Duration(seconds: 20);
  static const Duration timeoutRespuesta = Duration(seconds: 30);

  /// Zona horaria del colegio. Todas las fechas se muestran en esta zona.
  static const String zonaHoraria = 'America/Lima';

  static const String locale = 'es_PE';

  /// TTL de una solicitud de transferencia de sesión (contrato: 5 minutos).
  static const Duration ttlTransferencia = Duration(minutes: 5);

  /// Intervalo de sondeo del estado de la transferencia.
  static const Duration intervaloSondeoTransferencia = Duration(seconds: 5);
}
