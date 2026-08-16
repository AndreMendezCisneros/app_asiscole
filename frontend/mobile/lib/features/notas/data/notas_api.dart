import 'package:dio/dio.dart';

import '../../../core/error/api_error.dart';
import '../../../core/util/formato.dart';

class NotaSemanal {
  NotaSemanal({
    required this.id,
    required this.idRegistro,
    required this.nota,
    this.semanaCodigo,
    this.semanaEtiqueta,
    this.fechaInicio,
    this.fechaFin,
    this.notaMaxima,
    this.areaCodigo,
    this.areaNombre,
    this.carrera,
    this.registradoEn,
  });

  final String id;
  final int idRegistro;
  final String nota;
  final String? semanaCodigo;
  final String? semanaEtiqueta;
  final String? fechaInicio;
  final String? fechaFin;
  final String? notaMaxima;
  final String? areaCodigo;
  final String? areaNombre;
  final String? carrera;
  final String? registradoEn;

  String get tituloSemana {
    final etiqueta = (semanaEtiqueta ?? '').trim();
    if (etiqueta.isNotEmpty) return etiqueta;
    final codigo = (semanaCodigo ?? '').trim();
    if (codigo.isNotEmpty) return _semanaDesdeCodigo(codigo) ?? codigo;
    return 'Nota semanal';
  }

  String get rangoFechas {
    final inicio = _fechaLarga(fechaInicio);
    final fin = _fechaLarga(fechaFin);
    if (inicio != null && fin != null) {
      if (inicio == fin) return inicio;
      return 'Del $inicio al $fin';
    }
    return inicio ?? fin ?? '';
  }

  String get notaFormateada {
    final maximo = (notaMaxima ?? '').trim();
    if (maximo.isEmpty) return nota;
    return '$nota / $maximo';
  }

  String get fechaRegistro {
    final crudo = (registradoEn ?? '').trim();
    if (crudo.isEmpty) return '';
    try {
      return FechasLima.fechaLarga(parseInstanteApi(crudo));
    } catch (_) {
      return _fechaLarga(crudo) ?? '';
    }
  }

  static String? _semanaDesdeCodigo(String codigo) {
    final m = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(codigo.trim());
    if (m == null) return null;
    return 'Semana ${int.parse(m.group(2)!)}';
  }

  static const _meses = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static String? _fechaLarga(String? iso) {
    if (iso == null || iso.length < 10) return null;
    final p = iso.substring(0, 10).split('-');
    if (p.length != 3) return null;
    final anio = int.tryParse(p[0]);
    final mes = int.tryParse(p[1]);
    final dia = int.tryParse(p[2]);
    if (anio == null || mes == null || dia == null) return null;
    if (mes < 1 || mes > 12) return null;
    return '$dia de ${_meses[mes - 1]} de $anio';
  }

  factory NotaSemanal.fromJson(Map<String, dynamic> json) => NotaSemanal(
        id: json['id'] as String? ?? '',
        idRegistro: (json['id_registro'] as num?)?.toInt() ?? 0,
        nota: json['nota'] as String? ?? '',
        semanaCodigo: json['semana_codigo'] as String?,
        semanaEtiqueta: json['semana_etiqueta'] as String?,
        fechaInicio: json['fecha_inicio'] as String?,
        fechaFin: json['fecha_fin'] as String?,
        notaMaxima: json['nota_maxima'] as String?,
        areaCodigo: json['area_codigo'] as String?,
        areaNombre: json['area_nombre'] as String?,
        carrera: json['carrera'] as String?,
        registradoEn: json['registrado_en'] as String?,
      );
}

class NotasApi {
  NotasApi(this._dio);
  final Dio _dio;

  Future<List<NotaSemanal>> listar(int estudianteId) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/notas',
        queryParameters: {'estudiante_id': estudianteId},
      );
      final crudos = resp.data?['items'];
      if (crudos is! List) return [];
      return crudos
          .whereType<Map>()
          .map((e) => NotaSemanal.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }
}
