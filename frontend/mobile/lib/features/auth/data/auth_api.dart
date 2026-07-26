import 'package:dio/dio.dart';

import '../../../core/network/auth_interceptor.dart';
import '../domain/sesion.dart';
import '../domain/solicitud_transferencia.dart';

/// Llamadas HTTP de `/auth/*` del contrato (`docs/openapi.yaml`).
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<Sesion> login({
    required String telefono,
    required String documentoEstudiante,
    required String deviceId,
    String? modelo,
    String? sistemaOperativo,
    String? pushToken,
    String? alias,
  }) async {
    final respuesta = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      options: OpcionesAuth.con(EsquemaAuth.ninguno),
      data: {
        'telefono': telefono,
        'documento_estudiante': documentoEstudiante,
        'device_id': deviceId,
        'modelo': ?modelo,
        'sistema_operativo': ?sistemaOperativo,
        'push_token': ?pushToken,
        if (alias != null && alias.isNotEmpty) 'alias': alias,
      },
    );
    return Sesion.fromJson(respuesta.data ?? const {});
  }

  /// Renueva el token corto con el `session_token`. No dispara refresco propio:
  /// el interceptor solo reacciona a los 401 del esquema de datos.
  Future<DataTokenEmitido> refrescarDatos() async {
    final respuesta = await _dio.post<Map<String, dynamic>>(
      '/auth/refresh-data',
      options: OpcionesAuth.con(EsquemaAuth.sesion),
    );
    return DataTokenEmitido.fromJson(respuesta.data ?? const {});
  }

  /// Rota el `session_token` dentro de la ventana del día 7 al 10 (RF-A07).
  Future<Sesion> renovarSesion() async {
    final respuesta = await _dio.post<Map<String, dynamic>>(
      '/auth/renew-session',
      options: OpcionesAuth.con(EsquemaAuth.sesion),
    );
    return Sesion.fromJson(respuesta.data ?? const {});
  }

  Future<void> logout() => _dio.post<void>(
        '/auth/logout',
        options: OpcionesAuth.con(EsquemaAuth.sesion),
      );

  Future<SolicitudTransferencia> solicitarTransferencia({
    required String telefono,
    required String documentoEstudiante,
    required String deviceId,
  }) async {
    final respuesta = await _dio.post<Map<String, dynamic>>(
      '/auth/session-transfer/request',
      options: OpcionesAuth.con(EsquemaAuth.ninguno),
      data: {
        'telefono': telefono,
        'documento_estudiante': documentoEstudiante,
        'device_id': deviceId,
      },
    );
    return SolicitudTransferencia.fromJson(respuesta.data ?? const {});
  }

  Future<SolicitudTransferencia> consultarTransferencia(String id) async {
    final respuesta = await _dio.get<Map<String, dynamic>>(
      '/auth/session-transfer/$id',
      options: OpcionesAuth.con(EsquemaAuth.ninguno),
    );
    return SolicitudTransferencia.fromJson(respuesta.data ?? const {});
  }

  Future<void> aprobarTransferencia(String id) => _dio.post<void>(
        '/auth/session-transfer/$id/approve',
        options: OpcionesAuth.con(EsquemaAuth.sesion),
      );

  Future<void> rechazarTransferencia(String id) => _dio.post<void>(
        '/auth/session-transfer/$id/reject',
        options: OpcionesAuth.con(EsquemaAuth.sesion),
      );
}
