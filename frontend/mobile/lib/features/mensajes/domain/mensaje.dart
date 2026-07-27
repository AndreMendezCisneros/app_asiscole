import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../../core/util/formato.dart';

/// Mensaje ya renderizado por el backend. La app solo lo muestra.
class Mensaje extends Equatable {
  const Mensaje({
    required this.id,
    required this.tipo,
    required this.texto,
    required this.emitidoEn,
    this.emitidoEnRaw,
    this.colegio,
    this.estudianteId,
    this.estudianteNombre,
    this.entregado = false,
    this.leido = false,
    this.metadata = const {},
  });

  final String id;
  final String tipo;
  final String texto;
  final DateTime emitidoEn;
  final String? emitidoEnRaw;
  final String? colegio;
  final int? estudianteId;
  final String? estudianteNombre;
  final bool entregado;
  final bool leido;
  final Map<String, dynamic> metadata;

  Mensaje copyWith({bool? entregado, bool? leido}) {
    return Mensaje(
      id: id,
      tipo: tipo,
      texto: texto,
      emitidoEn: emitidoEn,
      emitidoEnRaw: emitidoEnRaw,
      colegio: colegio,
      estudianteId: estudianteId,
      estudianteNombre: estudianteNombre,
      entregado: entregado ?? this.entregado,
      leido: leido ?? this.leido,
      metadata: metadata,
    );
  }

  factory Mensaje.fromJson(Map<String, dynamic> json) {
    final crudo = json['emitido_en'] as String;
    return Mensaje(
      id: json['id'] as String,
      tipo: json['tipo'] as String,
      texto: json['texto'] as String,
      colegio: json['colegio'] as String?,
      estudianteId: json['estudiante_id'] as int?,
      estudianteNombre: json['estudiante_nombre'] as String?,
      emitidoEn: parseInstanteApi(crudo),
      emitidoEnRaw: crudo,
      entregado: json['entregado'] as bool? ?? false,
      leido: json['leido'] as bool? ?? false,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }

  Map<String, Object?> toLocalRow() => {
        'id': id,
        'tipo': tipo,
        'texto': texto,
        'colegio': colegio,
        'estudiante_id': estudianteId,
        'estudiante_nombre': estudianteNombre,
        'emitido_en': emitidoEn.toUtc().toIso8601String(),
        'entregado': entregado,
        'leido': leido,
        'metadata': metadata,
      };

  factory Mensaje.fromLocal(Map<String, Object?> row) {
    Map<String, dynamic> meta = const {};
    final crudoMeta = row['metadata'];
    if (crudoMeta is String && crudoMeta.isNotEmpty) {
      try {
        final decoded = jsonDecode(crudoMeta);
        if (decoded is Map) {
          meta = Map<String, dynamic>.from(decoded);
        }
      } on Object {
        meta = const {};
      }
    } else if (crudoMeta is Map) {
      meta = Map<String, dynamic>.from(crudoMeta);
    }
    return Mensaje(
      id: row['id']! as String,
      tipo: row['tipo']! as String,
      texto: row['texto']! as String,
      colegio: row['colegio'] as String?,
      estudianteId: row['estudiante_id'] as int?,
      estudianteNombre: row['estudiante_nombre'] as String?,
      emitidoEn: parseInstanteApi(row['emitido_en']! as String),
      emitidoEnRaw: row['emitido_en'] as String?,
      entregado: (row['entregado'] as int? ?? 0) == 1,
      leido: (row['leido'] as int? ?? 0) == 1,
      metadata: meta,
    );
  }

  @override
  List<Object?> get props => [id, leido, emitidoEn, entregado];
}
