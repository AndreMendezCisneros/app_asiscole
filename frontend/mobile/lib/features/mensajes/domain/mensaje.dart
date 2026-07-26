import 'package:equatable/equatable.dart';

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
  /// Valor exacto de `emitido_en` del API (para caché / `since`).
  final String? emitidoEnRaw;
  final String? colegio;
  final int? estudianteId;
  final String? estudianteNombre;
  final bool entregado;
  final bool leido;
  final Map<String, dynamic> metadata;

  factory Mensaje.fromJson(Map<String, dynamic> json) {
    final crudo = json['emitido_en'] as String;
    return Mensaje(
      id: json['id'] as String,
      tipo: json['tipo'] as String,
      texto: json['texto'] as String,
      colegio: json['colegio'] as String?,
      estudianteId: json['estudiante_id'] as int?,
      estudianteNombre: json['estudiante_nombre'] as String?,
      emitidoEn: DateTime.parse(crudo),
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
        // Misma cadena que mandó el API (con offset). Evita reescribir a UTC/Z
        // y romper marcas de sincronización si se vuelve a usar `since`.
        'emitido_en': emitidoEnRaw ?? emitidoEn.toIso8601String(),
        'entregado': entregado,
        'leido': leido,
        'metadata': metadata,
      };

  factory Mensaje.fromLocal(Map<String, Object?> row) {
    return Mensaje(
      id: row['id']! as String,
      tipo: row['tipo']! as String,
      texto: row['texto']! as String,
      colegio: row['colegio'] as String?,
      estudianteId: row['estudiante_id'] as int?,
      estudianteNombre: row['estudiante_nombre'] as String?,
      emitidoEn: DateTime.parse(row['emitido_en']! as String),
      entregado: (row['entregado'] as int? ?? 0) == 1,
      leido: (row['leido'] as int? ?? 0) == 1,
      metadata: const {},
    );
  }

  @override
  List<Object?> get props => [id, leido, emitidoEn];
}
