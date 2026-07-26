import 'package:equatable/equatable.dart';

import 'perfil.dart';

/// Respuesta de `/auth/login` y `/auth/renew-session`.
class Sesion extends Equatable {
  const Sesion({
    required this.sessionToken,
    this.sessionExpiraEn,
    required this.dataToken,
    this.dataExpiraEn,
    required this.perfil,
  });

  /// Token principal, 10 días. Solo se envía a `/auth/*`.
  final String sessionToken;
  final DateTime? sessionExpiraEn;

  /// Token secundario, 15 a 60 minutos. Lo llevan los endpoints de negocio.
  final String dataToken;
  final DateTime? dataExpiraEn;

  final Perfil perfil;

  factory Sesion.fromJson(Map<String, dynamic> json) => Sesion(
        sessionToken: json['session_token'] as String? ?? '',
        sessionExpiraEn: _fecha(json['session_expira_en']),
        dataToken: json['data_token'] as String? ?? '',
        dataExpiraEn: _fecha(json['data_expira_en']),
        perfil: Perfil.fromJson(
          (json['perfil'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );

  @override
  List<Object?> get props =>
      [sessionToken, sessionExpiraEn, dataToken, dataExpiraEn, perfil];
}

/// Respuesta de `/auth/refresh-data`.
class DataTokenEmitido extends Equatable {
  const DataTokenEmitido({required this.dataToken, this.dataExpiraEn});

  final String dataToken;
  final DateTime? dataExpiraEn;

  factory DataTokenEmitido.fromJson(Map<String, dynamic> json) =>
      DataTokenEmitido(
        dataToken: json['data_token'] as String? ?? '',
        dataExpiraEn: _fecha(json['data_expira_en']),
      );

  @override
  List<Object?> get props => [dataToken, dataExpiraEn];
}

DateTime? _fecha(Object? valor) =>
    valor is String ? DateTime.tryParse(valor)?.toUtc() : null;
