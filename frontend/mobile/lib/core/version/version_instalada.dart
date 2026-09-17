import 'package:package_info_plus/package_info_plus.dart';

/// `versionCode` del APK instalado, leído fuera del camino de arranque.
///
/// Resolverlo pide un salto al canal de plataforma y antes se hacía dentro de
/// `configurarInyector()`, es decir, antes del primer frame. El backend es
/// tolerante: una petición sin `X-App-Version` no se bloquea, así que basta con
/// tenerlo listo antes de consultar `/sistema/version-app`.
class VersionInstalada {
  const VersionInstalada._();

  static String _codigo = '';

  /// Cadena vacía mientras no se haya podido leer.
  static String get codigo => _codigo;

  static Future<String> cargar() async {
    if (_codigo.isNotEmpty) return _codigo;
    try {
      _codigo = (await PackageInfo.fromPlatform()).buildNumber;
    } on Object {
      // Tests y plataformas sin PackageInfo: se omite la cabecera.
    }
    return _codigo;
  }
}
