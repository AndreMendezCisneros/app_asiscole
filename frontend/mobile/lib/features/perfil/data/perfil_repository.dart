import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/error/api_error.dart';
import '../../auth/domain/perfil.dart';

class EstudianteVinculado {
  EstudianteVinculado({
    required this.id,
    required this.nombre,
    required this.grado,
    required this.seccion,
    required this.colegio,
    required this.activo,
  });

  final int id;
  final String nombre;
  final String grado;
  final String seccion;
  final String colegio;
  final bool activo;

  factory EstudianteVinculado.fromJson(Map<String, dynamic> json) =>
      EstudianteVinculado(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        grado: json['grado'] as String? ?? '',
        seccion: json['seccion'] as String? ?? '',
        colegio: json['colegio'] as String? ?? '',
        activo: json['activo'] as bool? ?? false,
      );
}

class PerfilRepository {
  PerfilRepository(this._dio);
  final Dio _dio;

  Perfil? _perfilCache;
  DateTime? _perfilCacheEn;
  List<EstudianteVinculado>? _estudiantesCache;
  DateTime? _estudiantesCacheEn;
  static const _ttl = Duration(seconds: 45);

  /// Se incrementa al cambiar el estudiante activo para que otras pestañas
  /// (IndexedStack) recarguen sin ir a Perfil.
  final ValueNotifier<int> estudianteActivoEpoch = ValueNotifier(0);

  void _avisarCambioEstudianteActivo() {
    estudianteActivoEpoch.value++;
  }

  Future<Perfil> obtener({bool forzar = false}) async {
    final ahora = DateTime.now();
    if (!forzar &&
        _perfilCache != null &&
        _perfilCacheEn != null &&
        ahora.difference(_perfilCacheEn!) < _ttl) {
      return _perfilCache!;
    }
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/perfil');
      final perfil = Perfil.fromJson(resp.data!);
      _perfilCache = perfil;
      _perfilCacheEn = ahora;
      return perfil;
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  Future<List<EstudianteVinculado>> estudiantes({bool forzar = false}) async {
    final ahora = DateTime.now();
    if (!forzar &&
        _estudiantesCache != null &&
        _estudiantesCacheEn != null &&
        ahora.difference(_estudiantesCacheEn!) < _ttl) {
      return _estudiantesCache!;
    }
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/perfil/estudiantes');
      final crudos = resp.data?['items'];
      if (crudos is! List) {
        _estudiantesCache = [];
        _estudiantesCacheEn = ahora;
        return [];
      }
      final lista = crudos
          .whereType<Map>()
          .map((e) => EstudianteVinculado.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _estudiantesCache = lista;
      _estudiantesCacheEn = ahora;
      return lista;
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  Future<Perfil> seleccionarEstudiante(int id) async {
    try {
      final resp = await _dio.patch<Map<String, dynamic>>(
        '/perfil',
        data: {'estudiante_activo_id': id},
      );
      final perfil = Perfil.fromJson(resp.data!);
      _perfilCache = perfil;
      _perfilCacheEn = DateTime.now();
      _estudiantesCache = null;
      _estudiantesCacheEn = null;
      _avisarCambioEstudianteActivo();
      return perfil;
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  Future<Perfil> actualizarAlias(String alias) async {
    try {
      final resp = await _dio.patch<Map<String, dynamic>>(
        '/perfil',
        data: {'alias': alias.trim()},
      );
      final perfil = Perfil.fromJson(resp.data!);
      _perfilCache = perfil;
      _perfilCacheEn = DateTime.now();
      return perfil;
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  void invalidarCache() {
    _perfilCache = null;
    _perfilCacheEn = null;
    _estudiantesCache = null;
    _estudiantesCacheEn = null;
    _ultimoTokenPush = null;
  }

  Future<void> eliminarCuenta(String documento) async {
    try {
      await _dio.post<void>(
        '/perfil/eliminar-cuenta',
        data: {'documento_estudiante': documento},
      );
      invalidarCache();
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  String? _ultimoTokenPush;

  /// Registra o actualiza el token FCM/APNs del dispositivo (RF push).
  Future<void> registrarPushToken({
    required String token,
    required String plataforma,
  }) async {
    if (_ultimoTokenPush == token) return;
    try {
      await _dio.put<void>(
        '/perfil/push-token',
        data: {
          'token': token,
          'plataforma': plataforma,
        },
      );
      _ultimoTokenPush = token;
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }
}
