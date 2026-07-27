import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../error/api_error.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';

/// Cliente HTTP de la app. Todas las llamadas pasan por aquí.
class ApiClient {
  ApiClient({
    required TokenStore tokens,
    required RefrescarDatos refrescar,
    void Function(ApiError motivo)? alInvalidarSesion,
    String? baseUrl,
    Dio? dio,
  }) {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl ?? Env.baseUrl,
            connectTimeout: Env.timeoutConexion,
            receiveTimeout: Env.timeoutRespuesta,
            sendTimeout: Env.timeoutRespuesta,
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
          ),
        );

    _dio.interceptors.add(
      AuthInterceptor(
        tokens: tokens,
        refrescar: refrescar,
        dioReintento: () => _dio,
        alInvalidarSesion: alInvalidarSesion,
      ),
    );

    if (kDebugMode) {
      developer.log('API baseUrl=${baseUrl ?? Env.baseUrl}', name: 'api');
      _dio.interceptors.add(_TrazaSinDatosPersonales());
      _dio.interceptors.add(_MedicionBytesDebug());
    }
  }

  late final Dio _dio;

  Dio get dio => _dio;
}

/// Traza mínima para depurar. Nunca registra cuerpos, teléfonos, documentos ni
/// texto de mensajes: solo verbo, ruta, estado y `request_id` (Ley 29733).
class _TrazaSinDatosPersonales extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    developer.log(
      '${response.requestOptions.method} ${response.requestOptions.path} '
      '-> ${response.statusCode}',
      name: 'api',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final error = ApiError.deDio(err);
    developer.log(
      '${err.requestOptions.method} ${err.requestOptions.path} '
      '-> ${error.statusCode} ${error.codigo} request_id=${error.requestId}',
      name: 'api',
    );
    handler.next(err);
  }
}

/// En debug suma bytes de request/response (sin cuerpos ni PII) para estimar
/// consumo de datos en pruebas Wi‑Fi vs móvil.
class _MedicionBytesDebug extends Interceptor {
  static int enviados = 0;
  static int recibidos = 0;

  int _tamano(dynamic data) {
    if (data == null) return 0;
    if (data is List<int>) return data.length;
    return data.toString().length;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    enviados += _tamano(options.data);
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final cl = response.headers.value('content-length');
    final n = cl == null ? null : int.tryParse(cl);
    if (n != null) {
      recibidos += n;
    } else {
      recibidos += _tamano(response.data);
    }
    developer.log(
      'bytes ≈ enviados=$enviados recibidos=$recibidos '
      '(${response.requestOptions.method} ${response.requestOptions.path})',
      name: 'api.bytes',
    );
    handler.next(response);
  }
}