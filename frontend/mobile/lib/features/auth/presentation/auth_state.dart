import 'package:equatable/equatable.dart';

import '../domain/perfil.dart';
import '../domain/solicitud_transferencia.dart';

/// Credenciales del intento en curso. Viven solo en memoria: nunca se guardan
/// ni se registran en trazas (Ley 29733).
class CredencialesLogin extends Equatable {
  const CredencialesLogin({
    required this.telefono,
    required this.documentoEstudiante,
  });

  /// Teléfono en E.164, por ejemplo `+51987654321`.
  final String telefono;

  /// Documento del estudiante (`estudiantes.codigo_barras`).
  final String documentoEstudiante;

  @override
  List<Object?> get props => [telefono, documentoEstudiante];

  @override
  String toString() => 'CredencialesLogin(oculto)';
}

/// Máquina de estados de la sesión, §7.3 del SRS.
sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => const [];
}

/// Sin sesión. Si viene de un fallo, [codigoError] dice cuál.
final class Unauthenticated extends AuthState {
  const Unauthenticated({this.codigoError, this.mensaje});

  final String? codigoError;
  final String? mensaje;

  @override
  List<Object?> get props => [codigoError, mensaje];
}

/// Login o restauración de sesión en curso.
final class Authenticating extends AuthState {
  const Authenticating();
}

/// Sesión válida y con red: la app sincroniza con el backend.
final class OnlineSync extends AuthState {
  const OnlineSync(this.perfil);

  final Perfil perfil;

  @override
  List<Object?> get props => [perfil];
}

/// Sesión válida sin red: solo se leen los mensajes ya cacheados.
final class OfflineMessagesOnly extends AuthState {
  const OfflineMessagesOnly(this.perfil);

  final Perfil? perfil;

  @override
  List<Object?> get props => [perfil];
}

/// 409 SESSION_ALREADY_ACTIVE: la cuenta ya tiene sesión en otro dispositivo.
final class LoginDenied extends AuthState {
  const LoginDenied({
    required this.credenciales,
    required this.mensaje,
    this.solicitando = false,
    this.errorSolicitud,
  });

  final CredencialesLogin credenciales;
  final String mensaje;

  /// La solicitud de traspaso está en vuelo.
  final bool solicitando;

  /// Código del fallo al pedir el traspaso, por ejemplo TOO_MANY_REQUESTS.
  final String? errorSolicitud;

  LoginDenied copyWith({bool? solicitando, String? errorSolicitud}) =>
      LoginDenied(
        credenciales: credenciales,
        mensaje: mensaje,
        solicitando: solicitando ?? this.solicitando,
        errorSolicitud: errorSolicitud,
      );

  @override
  List<Object?> get props =>
      [credenciales, mensaje, solicitando, errorSolicitud];
}

/// Traspaso pedido: se espera que el dispositivo activo apruebe o rechace.
final class AwaitingTransferApproval extends AuthState {
  const AwaitingTransferApproval({
    required this.solicitud,
    required this.credenciales,
  });

  final SolicitudTransferencia solicitud;
  final CredencialesLogin credenciales;

  @override
  List<Object?> get props => [solicitud, credenciales];
}

/// 403 ACCOUNT_SUSPENDED. El motivo lo redacta el backend.
final class Suspended extends AuthState {
  const Suspended({this.motivo});

  final String? motivo;

  @override
  List<Object?> get props => [motivo];
}
