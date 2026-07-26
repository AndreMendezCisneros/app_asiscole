import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Envoltorio del almacén cifrado del dispositivo.
///
/// Los tokens de sesión y de datos viven aquí, nunca en `SharedPreferences`.
class SecureStorage {
  SecureStorage([FlutterSecureStorage? almacen])
      : _almacen = almacen ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

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
}
