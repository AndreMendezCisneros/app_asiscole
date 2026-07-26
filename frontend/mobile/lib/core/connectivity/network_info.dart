import 'package:connectivity_plus/connectivity_plus.dart';

/// Estado de conectividad del dispositivo.
///
/// Solo indica si hay una interfaz de red; que el backend responda es otra cosa
/// y la resuelve la capa de red con sus errores.
class NetworkInfo {
  NetworkInfo([Connectivity? conectividad])
      : _conectividad = conectividad ?? Connectivity();

  final Connectivity _conectividad;

  Future<bool> get hayConexion async =>
      _tieneRed(await _conectividad.checkConnectivity());

  Stream<bool> get cambios =>
      _conectividad.onConnectivityChanged.map(_tieneRed).distinct();

  bool _tieneRed(List<ConnectivityResult> resultados) =>
      resultados.any((r) => r != ConnectivityResult.none);
}
