import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import 'error_codes.dart';

/// Error normalizado de la API: `{code, message, request_id}` del contrato.
class ApiError extends Equatable implements Exception {
  const ApiError({
    required this.codigo,
    required this.mensaje,
    this.requestId,
    this.statusCode,
  });

  final String codigo;
  final String mensaje;
  final String? requestId;
  final int? statusCode;

  factory ApiError.local(String codigo, {int? statusCode}) => ApiError(
        codigo: codigo,
        mensaje: CodigosError.mensajePorDefecto(codigo),
        statusCode: statusCode,
      );

  /// Traduce cualquier fallo de Dio al modelo de error del contrato.
  factory ApiError.deDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (e.response == null) return ApiError.local(CodigosError.sinConexion);
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiError.local(CodigosError.tiempoAgotado);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
        break;
    }

    final respuesta = e.response;
    final cuerpo = respuesta?.data;
    if (cuerpo is Map) {
      final codigo = cuerpo['code'];
      if (codigo is String && codigo.isNotEmpty) {
        final mensaje = cuerpo['message'];
        return ApiError(
          codigo: codigo,
          mensaje: mensaje is String && mensaje.isNotEmpty
              ? mensaje
              : CodigosError.mensajePorDefecto(codigo),
          requestId: cuerpo['request_id'] as String?,
          statusCode: respuesta?.statusCode,
        );
      }
    }

    return ApiError(
      codigo: _codigoPorEstado(respuesta?.statusCode),
      mensaje:
          CodigosError.mensajePorDefecto(_codigoPorEstado(respuesta?.statusCode)),
      statusCode: respuesta?.statusCode,
    );
  }

  /// Código deducido del estado HTTP cuando la respuesta no trae `code`.
  ///
  /// 403 y 404 se quedan fuera a propósito: un HTML del proxy (Caddy, un WAF)
  /// no es una cuenta suspendida ni un vínculo inexistente, y traducirlo así
  /// cerraba la sesión del apoderado por un problema de infraestructura.
  /// `ACCOUNT_SUSPENDED` y `STUDENT_LINK_NOT_FOUND` solo llegan del canal, que
  /// siempre responde con el cuerpo del contrato.
  static String _codigoPorEstado(int? status) => switch (status) {
        400 => CodigosError.validacion,
        401 => CodigosError.noAutenticado,
        409 => CodigosError.sesionYaActiva,
        410 => CodigosError.sesionExpirada,
        423 => CodigosError.cuentaBloqueada,
        429 => CodigosError.demasiadasSolicitudes,
        503 => CodigosError.bdColegioNoDisponible,
        _ => CodigosError.errorInesperado,
      };

  bool get esSinConexion => codigo == CodigosError.sinConexion;

  @override
  List<Object?> get props => [codigo, mensaje, requestId, statusCode];

  /// Sin datos personales: solo código, estado y correlación.
  @override
  String toString() =>
      'ApiError(codigo: $codigo, status: $statusCode, request_id: $requestId)';
}
