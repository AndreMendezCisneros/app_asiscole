/// Catálogo de códigos de error del contrato (`docs/openapi.yaml`).
///
/// La UI reacciona siempre a estos códigos, nunca al texto del mensaje.
class CodigosError {
  const CodigosError._();

  static const String validacion = 'VALIDATION_ERROR';
  static const String noAutenticado = 'UNAUTHENTICATED';
  static const String cuentaSuspendida = 'ACCOUNT_SUSPENDED';
  static const String rolNoPermitido = 'ROLE_NOT_ALLOWED';
  static const String vinculoNoEncontrado = 'STUDENT_LINK_NOT_FOUND';
  static const String sesionYaActiva = 'SESSION_ALREADY_ACTIVE';
  static const String transferenciaYaPendiente = 'TRANSFER_ALREADY_PENDING';
  static const String sesionExpirada = 'SESSION_EXPIRED';
  static const String transferenciaExpirada = 'TRANSFER_EXPIRED';
  static const String cuentaBloqueada = 'ACCOUNT_LOCKED';
  static const String demasiadasSolicitudes = 'TOO_MANY_REQUESTS';
  static const String bdColegioNoDisponible = 'UPSTREAM_SCHOOL_DB_UNAVAILABLE';

  /// Códigos locales, no provienen del backend.
  static const String sinConexion = 'SIN_CONEXION';
  static const String tiempoAgotado = 'TIEMPO_AGOTADO';
  static const String errorInesperado = 'ERROR_INESPERADO';

  /// Mensajes de respaldo por si el backend no envía texto.
  static const Map<String, String> _respaldo = {
    validacion: 'Revisa los datos ingresados.',
    noAutenticado: 'Tu sesión no es válida. Vuelve a iniciar sesión.',
    cuentaSuspendida: 'Tu cuenta está suspendida.',
    rolNoPermitido: 'No tienes permiso para ver esta información.',
    vinculoNoEncontrado:
        'No encontramos una cuenta con esos datos. Verifícalos con el colegio.',
    sesionYaActiva: 'Ya tienes una sesión activa en otro dispositivo.',
    transferenciaYaPendiente:
        'Ya hay una solicitud de acceso en curso. Espera la respuesta.',
    sesionExpirada: 'Tu sesión venció. Inicia sesión otra vez.',
    transferenciaExpirada: 'La solicitud de acceso expiró.',
    cuentaBloqueada:
        'Cuenta bloqueada temporalmente por intentos fallidos. Espera unos minutos.',
    demasiadasSolicitudes: 'Demasiados intentos. Inténtalo más tarde.',
    bdColegioNoDisponible:
        'El sistema del colegio no responde en este momento. Inténtalo más tarde.',
    sinConexion: 'Sin conexión a internet.',
    tiempoAgotado: 'El servidor tardó demasiado en responder.',
    errorInesperado: 'Ocurrió un problema. Inténtalo de nuevo.',
  };

  static String mensajePorDefecto(String codigo) =>
      _respaldo[codigo] ?? _respaldo[errorInesperado]!;
}
