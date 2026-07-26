import 'package:equatable/equatable.dart';

enum EstadoTransferencia {
  pendiente('pending'),
  aprobada('approved'),
  rechazada('rejected'),
  expirada('expired');

  const EstadoTransferencia(this.api);

  final String api;

  static EstadoTransferencia desdeApi(String? valor) =>
      EstadoTransferencia.values.firstWhere(
        (e) => e.api == valor,
        orElse: () => EstadoTransferencia.pendiente,
      );
}

/// Solicitud de traspaso de sesión al dispositivo nuevo (TTL de 5 minutos).
class SolicitudTransferencia extends Equatable {
  const SolicitudTransferencia({
    required this.id,
    required this.estado,
    this.expiraEn,
  });

  final String id;
  final EstadoTransferencia estado;
  final DateTime? expiraEn;

  bool get estaPendiente => estado == EstadoTransferencia.pendiente;

  /// Tiempo que queda antes de que el backend la dé por vencida.
  Duration get restante {
    final limite = expiraEn;
    if (limite == null) return Duration.zero;
    final falta = limite.difference(DateTime.now().toUtc());
    return falta.isNegative ? Duration.zero : falta;
  }

  factory SolicitudTransferencia.fromJson(Map<String, dynamic> json) =>
      SolicitudTransferencia(
        id: '${json['id'] ?? ''}',
        estado: EstadoTransferencia.desdeApi(json['estado'] as String?),
        expiraEn: json['expira_en'] is String
            ? DateTime.tryParse(json['expira_en'] as String)?.toUtc()
            : null,
      );

  @override
  List<Object?> get props => [id, estado, expiraEn];
}
