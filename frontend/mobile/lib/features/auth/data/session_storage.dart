import 'dart:convert';

import '../../../core/device/info_dispositivo.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/storage/token_store.dart';
import '../domain/perfil.dart';
import '../domain/sesion.dart';

/// Almacén cifrado de la sesión: ambos tokens, sus vencimientos, el perfil
/// y el identificador de esta instalación.
///
/// Implementa [TokenStore] para que la capa de red no dependa de la feature.
class SessionStorage implements TokenStore {
  SessionStorage(this._almacen);

  final SecureStorage _almacen;

  static const _claveSessionToken = 'session_token';
  static const _claveSessionExpira = 'session_expira_en';
  static const _claveDataToken = 'data_token';
  static const _claveDataExpira = 'data_expira_en';
  static const _clavePerfil = 'perfil';
  static const _claveDeviceId = 'device_id';

  @override
  Future<String?> leerSessionToken() => _almacen.leer(_claveSessionToken);

  @override
  Future<String?> leerDataToken() => _almacen.leer(_claveDataToken);

  @override
  Future<void> guardarDataToken(String token, DateTime? expiraEn) async {
    await _almacen.escribir(_claveDataToken, token);
    await _almacen.escribir(_claveDataExpira, expiraEn?.toIso8601String());
  }

  /// Borra los tokens y el perfil. La caché de mensajes no se toca.
  @override
  Future<void> limpiarTokens() async {
    await _almacen.borrar(_claveSessionToken);
    await _almacen.borrar(_claveSessionExpira);
    await _almacen.borrar(_claveDataToken);
    await _almacen.borrar(_claveDataExpira);
    await _almacen.borrar(_clavePerfil);
  }

  Future<void> guardarSesion(Sesion sesion) async {
    await _almacen.escribir(_claveSessionToken, sesion.sessionToken);
    await _almacen.escribir(
      _claveSessionExpira,
      sesion.sessionExpiraEn?.toIso8601String(),
    );
    await guardarDataToken(sesion.dataToken, sesion.dataExpiraEn);
    await guardarPerfil(sesion.perfil);
  }

  Future<void> guardarPerfil(Perfil perfil) =>
      _almacen.escribir(_clavePerfil, jsonEncode(perfil.toJson()));

  Future<Perfil?> leerPerfil() async {
    final crudo = await _almacen.leer(_clavePerfil);
    if (crudo == null || crudo.isEmpty) return null;
    try {
      return Perfil.fromJson(jsonDecode(crudo) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  Future<DateTime?> leerSessionExpiraEn() async {
    final crudo = await _almacen.leer(_claveSessionExpira);
    return crudo == null ? null : DateTime.tryParse(crudo);
  }

  Future<bool> get haySesion async {
    final token = await leerSessionToken();
    return token != null && token.isNotEmpty;
  }

  /// La ventana de renovación del `session_token` es del día 7 al 10 (RF-A07).
  Future<bool> get tocaRenovarSesion async {
    final expira = await leerSessionExpiraEn();
    if (expira == null) return false;
    final faltan = expira.difference(DateTime.now().toUtc());
    return !faltan.isNegative && faltan.inDays <= 3;
  }

  /// Identificador estable de la instalación. Se crea la primera vez y no
  /// contiene ningún dato personal.
  Future<String> deviceId() async {
    final guardado = await _almacen.leer(_claveDeviceId);
    if (guardado != null && guardado.isNotEmpty) return guardado;
    final nuevo = InfoDispositivo.generarDeviceId();
    await _almacen.escribir(_claveDeviceId, nuevo);
    return nuevo;
  }
}
