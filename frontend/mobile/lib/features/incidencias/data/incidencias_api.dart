import 'package:dio/dio.dart';

class IncidenciaResumen {
  IncidenciaResumen({
    required this.id,
    required this.fecha,
    required this.categoria,
    required this.falta,
    required this.esGrave,
    required this.reportadoPor,
  });

  final int id;
  final String fecha;
  final String categoria;
  final String falta;
  final bool esGrave;
  final String reportadoPor;

  factory IncidenciaResumen.fromJson(Map<String, dynamic> json) =>
      IncidenciaResumen(
        id: json['id'] as int,
        fecha: json['fecha'] as String,
        categoria: json['categoria'] as String,
        falta: json['falta'] as String,
        esGrave: json['es_grave'] as bool? ?? false,
        reportadoPor: json['reportado_por'] as String? ?? '',
      );
}

class IncidenciasApi {
  IncidenciasApi(this._dio);
  final Dio _dio;

  Future<List<IncidenciaResumen>> listar(int estudianteId) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/incidencias',
      queryParameters: {'estudiante_id': estudianteId},
    );
    return (resp.data?['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(IncidenciaResumen.fromJson)
        .toList();
  }
}
