import 'package:flutter/foundation.dart';

/// Configuración de entorno de la app.
///
/// Por defecto apunta al canal en el VPS:
/// `https://jeanpiaget.asiscole.com/canal-api/v0.1`
///
/// Sobrescribir (p. ej. Django local):
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/v0.1`
/// o `.\run_dispositivo.ps1 -Local`
class Env {
  const Env._();

  static const String _baseUrlDefinida =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Backend del canal en el VPS (Caddy → Django).
  static const String _produccion =
      'https://jeanpiaget.asiscole.com/canal-api/v0.1';

  static String get baseUrl {
    if (_baseUrlDefinida.isNotEmpty) return _baseUrlDefinida;
    return _produccion;
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
