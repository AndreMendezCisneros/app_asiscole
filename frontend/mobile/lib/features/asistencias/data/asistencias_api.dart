import 'package:dio/dio.dart';

import '../../../core/error/api_error.dart';

class DiaAsistencia {
  DiaAsistencia({
    required this.fecha,
    required this.estado,
    this.horaEntrada,
    this.horaSalida,
  });

  final String fecha;
  final String estado;
  final String? horaEntrada;
  final String? horaSalida;

  factory DiaAsistencia.fromJson(Map<String, dynamic> json) => DiaAsistencia(
        fecha: json['fecha'] as String,
        estado: json['estado'] as String,
        horaEntrada: json['hora_entrada'] as String?,
        horaSalida: json['hora_salida'] as String?,
      );
}

class AsistenciasApi {
  AsistenciasApi(this._dio);
  final Dio _dio;

  Future<List<DiaAsistencia>> mes({
    required int estudianteId,
    required int anio,
    required int mes,
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/asistencias',
        queryParameters: {
          'estudiante_id': estudianteId,
          'anio': anio,
          'mes': mes,
        },
      );
      final crudos = resp.data?['items'];
      if (crudos is! List) return [];
      return crudos
          .whereType<Map>()
          .map((e) => DiaAsistencia.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }
}
