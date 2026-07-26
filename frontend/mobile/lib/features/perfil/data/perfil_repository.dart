import 'package:dio/dio.dart';

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
        id: json['id'] as int,
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
    final resp = await _dio.get<Map<String, dynamic>>('/perfil');
    return Perfil.fromJson(resp.data!);
  }

  Future<List<EstudianteVinculado>> estudiantes() async {
    final resp = await _dio.get<Map<String, dynamic>>('/perfil/estudiantes');
    return (resp.data?['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(EstudianteVinculado.fromJson)
        .toList();
  }

  Future<Perfil> seleccionarEstudiante(int id) async {
    final resp = await _dio.patch<Map<String, dynamic>>(
      '/perfil',
      data: {'estudiante_activo_id': id},
    );
    return Perfil.fromJson(resp.data!);
  }

  Future<void> eliminarCuenta(String documento) async {
    await _dio.post<void>(
      '/perfil/eliminar-cuenta',
      data: {'documento_estudiante': documento},
    );
  }

  /// Registra o actualiza el token FCM/APNs del dispositivo (RF push).
  Future<void> registrarPushToken({
    required String token,
    required String plataforma,
  }) async {
    await _dio.put<void>(
      '/perfil/push-token',
      data: {
        'token': token,
        'plataforma': plataforma,
      },
    );
  }
}
