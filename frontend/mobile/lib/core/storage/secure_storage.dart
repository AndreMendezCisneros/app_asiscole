import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Envoltorio del almacén cifrado del dispositivo.
///
/// Los tokens de sesión y de datos viven aquí, nunca en `SharedPreferences`.
class SecureStorage {
  SecureStorage([FlutterSecureStorage? almacen])
      : _almacen = almacen ??
            const FlutterSecureStorage(
              // `this_device`: el token no viaja en el respaldo de iCloud a
              // otro iPhone, igual que en Android con `allowBackup=false`.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const String _claveInstalada = 'keychain_de_esta_instalacion';

  final FlutterSecureStorage _almacen;

  Future<String?> leer(String clave) => _almacen.read(key: clave);

  Future<void> escribir(String clave, String? valor) async {
    if (valor == null) {
      await _almacen.delete(key: clave);
      return;
    }
    await _almacen.write(key: clave, value: valor);
  }

  Future<void> borrar(String clave) => _almacen.delete(key: clave);

  Future<void> borrarTodo() => _almacen.deleteAll();

  /// En iOS el Keychain sobrevive a la desinstalación y `SharedPreferences`
  /// no. Sin esto, reinstalar revive la sesión y el `device_id` anteriores en
  /// un teléfono que pudo cambiar de dueño; en Android desinstalar ya lo borra.
  Future<void> olvidarSiEsInstalacionNueva() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_claveInstalada) ?? false) return;
      await borrarTodo();
      await prefs.setBool(_claveInstalada, true);
    } on Object {
      // Si falla, se reintenta en el siguiente arranque.
    }
  }
}
