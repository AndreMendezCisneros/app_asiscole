import 'package:dio/dio.dart';

import '../../../core/error/api_error.dart';

class IncidenciaResumen {
  IncidenciaResumen({
    required this.id,
    required this.fecha,
    required this.categoria,
    required this.falta,
    required this.esGrave,
    required this.reportadoPor,
    this.observaciones = '',
    this.confirmada = false,
    this.confirmadaEn,
  });

  final int id;
  final String fecha;
  final String categoria;
  final String falta;
  final bool esGrave;
  final String reportadoPor;

  /// Lo que escribió el auxiliar al registrar la falta. Vacío si no puso nada.
  ///
  /// Un backend anterior no manda la clave; entonces queda vacía y el detalle
  /// simplemente no muestra el bloque.
  final String observaciones;
  final bool confirmada;
  final String? confirmadaEn;

  IncidenciaResumen copyWith({bool? confirmada, String? confirmadaEn}) {
    return IncidenciaResumen(
      id: id,
      fecha: fecha,
      categoria: categoria,
      falta: falta,
      esGrave: esGrave,
      reportadoPor: reportadoPor,
      observaciones: observaciones,
      confirmada: confirmada ?? this.confirmada,
      confirmadaEn: confirmadaEn ?? this.confirmadaEn,
    );
  }

  factory IncidenciaResumen.fromJson(Map<String, dynamic> json) =>
      IncidenciaResumen(
        id: (json['id'] as num).toInt(),
        fecha: json['fecha'] as String,
        categoria: json['categoria'] as String,
        falta: json['falta'] as String,
        esGrave: json['es_grave'] as bool? ?? false,
        reportadoPor: json['reportado_por'] as String? ?? '',
        observaciones: (json['observaciones'] as String? ?? '').trim(),
        confirmada: json['confirmada'] as bool? ?? false,
        confirmadaEn: json['confirmada_en'] as String?,
      );
}

class IncidenciasApi {
  IncidenciasApi(this._dio);
  final Dio _dio;

  Future<List<IncidenciaResumen>> listar(int estudianteId) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/incidencias',
        queryParameters: {'estudiante_id': estudianteId},
      );
      final crudos = resp.data?['items'];
      if (crudos is! List) return [];
      return crudos
          .whereType<Map>()
          .map((e) => IncidenciaResumen.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }

  Future<void> confirmar({
    required int incidenciaId,
    required int estudianteId,
  }) async {
    try {
      await _dio.post<void>(
        '/incidencias/$incidenciaId/confirmar',
        queryParameters: {'estudiante_id': estudianteId},
      );
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }
}
