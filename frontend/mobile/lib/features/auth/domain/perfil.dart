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
  });

  final String? alias;
  final String telefono;
  final EstadoCuenta estado;
  final String? motivoSuspension;
  final int? estudianteActivoId;

  bool get estaSuspendido => estado == EstadoCuenta.suspendido;

  factory Perfil.fromJson(Map<String, dynamic> json) => Perfil(
        alias: json['alias'] as String?,
        telefono: json['telefono'] as String? ?? '',
        estado: EstadoCuenta.desdeApi(json['estado'] as String?),
        motivoSuspension: json['motivo_suspension'] as String?,
        estudianteActivoId: json['estudiante_activo_id'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'telefono': telefono,
        'estado': estado.api,
        'motivo_suspension': motivoSuspension,
        'estudiante_activo_id': estudianteActivoId,
      };

  Perfil copyWith({String? alias, int? estudianteActivoId}) => Perfil(
        alias: alias ?? this.alias,
        telefono: telefono,
        estado: estado,
        motivoSuspension: motivoSuspension,
        estudianteActivoId: estudianteActivoId ?? this.estudianteActivoId,
      );

  @override
  List<Object?> get props =>
      [alias, telefono, estado, motivoSuspension, estudianteActivoId];
}
