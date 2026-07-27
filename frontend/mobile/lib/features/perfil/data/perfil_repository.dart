import 'package:dio/dio.dart';

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

  Future<Perfil> obtener() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/perfil');
      return Perfil.fromJson(resp.data!);
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  Future<List<EstudianteVinculado>> estudiantes() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/perfil/estudiantes');
      final crudos = resp.data?['items'];
      if (crudos is! List) return [];
      return crudos
          .whereType<Map>()
          .map((e) => EstudianteVinculado.fromJson(Map<String, dynamic>.from(e)))
          .toList();
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
      return Perfil.fromJson(resp.data!);
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  Future<void> eliminarCuenta(String documento) async {
    try {
      await _dio.post<void>(
        '/perfil/eliminar-cuenta',
        data: {'documento_estudiante': documento},
      );
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  /// Registra o actualiza el token FCM/APNs del dispositivo (RF push).
  Future<void> registrarPushToken({
    required String token,
    required String plataforma,
  }) async {
    try {
      await _dio.put<void>(
        '/perfil/push-token',
        data: {
          'token': token,
          'plataforma': plataforma,
        },
      );
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }
}
