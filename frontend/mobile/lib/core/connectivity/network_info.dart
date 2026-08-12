import 'package:connectivity_plus/connectivity_plus.dart';

/// Estado de conectividad del dispositivo.
///
/// Solo indica si hay una interfaz de red; que el backend responda es otra cosa
/// y la resuelve la capa de red con sus errores.
///
/// En algunos Android (p. ej. MIUI) `connectivity_plus` emite `[]` al arrancar
/// o al abrir el teclado. Eso no significa “sin internet”: se trata como
/// desconocido y no se fuerza el modo offline.
class NetworkInfo {
  NetworkInfo([Connectivity? conectividad])
      : _conectividad = conectividad ?? Connectivity();

  final Connectivity _conectividad;

  Future<bool> get hayConexion async =>
      _tieneRed(await _conectividad.checkConnectivity());

  Stream<bool> get cambios =>
      _conectividad.onConnectivityChanged.map(_tieneRed).distinct();

  bool _tieneRed(List<ConnectivityResult> resultados) {
    // Lista vacía = estado desconocido (no “sin red”).
    if (resultados.isEmpty) return true;
    return resultados.any((r) => r != ConnectivityResult.none);
  }
}
