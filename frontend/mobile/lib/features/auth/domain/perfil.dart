import 'package:equatable/equatable.dart';

enum EstadoCuenta {
  activo,
  suspendido;

  static EstadoCuenta desdeApi(String? valor) =>
      valor == 'suspendido' ? EstadoCuenta.suspendido : EstadoCuenta.activo;

  String get api => name;
}

/// Perfil del apoderado, tal como lo entrega el contrato.
///
/// El teléfono llega ya enmascarado por el backend (`+51*****321`).
class Perfil extends Equatable {
  const Perfil({
    this.alias,
    required this.telefono,
    required this.estado,
    this.motivoSuspension,
    this.estudianteActivoId,
    this.terminosVersion,
    this.terminosAceptadosEn,
  });

  final String? alias;
  final String telefono;
  final EstadoCuenta estado;
  final String? motivoSuspension;
  final int? estudianteActivoId;
  final String? terminosVersion;
  final DateTime? terminosAceptadosEn;

  bool get estaSuspendido => estado == EstadoCuenta.suspendido;

  factory Perfil.fromJson(Map<String, dynamic> json) => Perfil(
        alias: json['alias'] as String?,
        telefono: json['telefono'] as String? ?? '',
        estado: EstadoCuenta.desdeApi(json['estado'] as String?),
        motivoSuspension: json['motivo_suspension'] as String?,
        estudianteActivoId: (json['estudiante_activo_id'] as num?)?.toInt(),
        terminosVersion: json['terminos_version'] as String?,
        terminosAceptadosEn: _fecha(json['terminos_aceptados_en']),
      );

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'telefono': telefono,
        'estado': estado.api,
        'motivo_suspension': motivoSuspension,
        'estudiante_activo_id': estudianteActivoId,
        'terminos_version': terminosVersion,
        'terminos_aceptados_en': terminosAceptadosEn?.toUtc().toIso8601String(),
      };

  Perfil copyWith({
    String? alias,
    int? estudianteActivoId,
    String? terminosVersion,
    DateTime? terminosAceptadosEn,
  }) =>
      Perfil(
        alias: alias ?? this.alias,
        telefono: telefono,
        estado: estado,
        motivoSuspension: motivoSuspension,
        estudianteActivoId: estudianteActivoId ?? this.estudianteActivoId,
        terminosVersion: terminosVersion ?? this.terminosVersion,
        terminosAceptadosEn: terminosAceptadosEn ?? this.terminosAceptadosEn,
      );

  @override
  List<Object?> get props => [
        alias,
        telefono,
        estado,
        motivoSuspension,
        estudianteActivoId,
        terminosVersion,
        terminosAceptadosEn,
      ];

  static DateTime? _fecha(Object? crudo) {
    if (crudo is! String || crudo.isEmpty) return null;
    return DateTime.tryParse(crudo);
  }
}
