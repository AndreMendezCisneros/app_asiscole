import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Configuración de entorno de la app.
///
/// El valor puede sobrescribirse en tiempo de compilación:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/v0.1`
///
/// Producción (release APK): backend en el VPS de Jean Piaget
/// `https://jeanpiaget.asiscole.com/canal-api/v0.1`
class Env {
  const Env._();

  static const String _baseUrlDefinida =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Backend del canal en el VPS (Caddy → Django en :8000).
  static const String _produccion =
      'https://jeanpiaget.asiscole.com/canal-api/v0.1';

  /// Celular físico en la misma Wi‑Fi que el PC de desarrollo.
  /// Si usas emulador Android, lanza con:
  /// `--dart-define=API_BASE_URL=http://10.0.2.2:8000/v0.1`
  /// Si cambia la IP de tu PC, actualiza esta constante o usa `--dart-define`.
  static const String _desarrolloAndroid = 'http://192.168.100.6:8000/v0.1';
  static const String _desarrolloOtros = 'http://localhost:8000/v0.1';

  static String get baseUrl {
    if (_baseUrlDefinida.isNotEmpty) return _baseUrlDefinida;
    if (kReleaseMode) return _produccion;
    if (!kIsWeb && Platform.isAndroid) return _desarrolloAndroid;
    return _desarrolloOtros;
  }

  static const Duration timeoutConexion = Duration(seconds: 15);
  static const Duration timeoutRespuesta = Duration(seconds: 20);

  /// Zona horaria del colegio. Todas las fechas se muestran en esta zona.
  static const String zonaHoraria = 'America/Lima';

  static const String locale = 'es_PE';

  /// TTL de una solicitud de transferencia de sesión (contrato: 5 minutos).
  static const Duration ttlTransferencia = Duration(minutes: 5);

  /// Intervalo de sondeo del estado de la transferencia.
  static const Duration intervaloSondeoTransferencia = Duration(seconds: 5);
}
