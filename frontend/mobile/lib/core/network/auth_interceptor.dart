import 'dart:async';

import 'package:dio/dio.dart';

import '../error/api_error.dart';
import '../storage/token_store.dart';

/// Qué token lleva cada petición, según el contrato.
enum EsquemaAuth {
  /// Endpoint público: `/auth/login`, `/auth/session-transfer/request`…
  ninguno,

  /// `session_token` (10 días). Solo para `/auth/*`.
  sesion,

  /// `data_token` (15 a 60 min). Todos los endpoints de negocio.
  datos,
}

/// Claves que la capa de datos deja en `Options.extra` para el interceptor.
class OpcionesAuth {
  const OpcionesAuth._();

  static const String claveEsquema = 'asiscole_esquema_auth';
  static const String claveReintento = 'asiscole_reintentado';

  static Options con(EsquemaAuth esquema) =>
      Options(extra: {claveEsquema: esquema});
}

/// Resultado de renovar el token corto.
typedef DataTokenRenovado = ({String token, DateTime? expiraEn});

/// Llama a `POST /auth/refresh-data` con el `session_token`.
typedef RefrescarDatos = Future<DataTokenRenovado> Function();

/// Pone el token que corresponde en cada petición y renueva el `data_token`
/// de forma transparente cuando caduca.
///
/// Un 401 en un endpoint de negocio dispara `POST /auth/refresh-data` y el
/// reintento de la petición original una sola vez. Si varias peticiones fallan
/// a la vez, todas esperan al **mismo** refresco: el `Completer` de
/// `_refrescoEnCurso` hace de candado.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStore tokens,
    required RefrescarDatos refrescar,
    required Dio Function() dioReintento,
    this.alInvalidarSesion,
  })  : _tokens = tokens,
        _refrescar = refrescar,
        _dioReintento = dioReintento;

  final TokenStore _tokens;
  final RefrescarDatos _refrescar;
  final Dio Function() _dioReintento;

  /// Se avisa cuando la sesión deja de ser usable (401, 410 o 403 al refrescar).
  final void Function(ApiError motivo)? alInvalidarSesion;

  Completer<String?>? _refrescoEnCurso;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final esquema =
        options.extra[OpcionesAuth.claveEsquema] as EsquemaAuth? ??
            EsquemaAuth.datos;

    final token = switch (esquema) {
      EsquemaAuth.ninguno => null,
      EsquemaAuth.sesion => await _tokens.leerSessionToken(),
      EsquemaAuth.datos => await _tokens.leerDataToken(),
    };

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    } else {
      options.headers.remove('Authorization');
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_procedeRenovar(err)) {
      handler.next(err);
      return;
    }

    final peticion = err.requestOptions;
    final sessionToken = await _tokens.leerSessionToken();
    if (sessionToken == null || sessionToken.isEmpty) {
      await _invalidarSesion(ApiError.deDio(err));
      handler.next(err);
      return;
    }

    // Si otra petición ya renovó mientras esta viajaba, se reintenta con el
    // token nuevo sin pedir uno más.
    final tokenActual = await _tokens.leerDataToken();
    final tokenUsado = _tokenDeLaPeticion(peticion);
    final nuevoToken = (tokenActual != null &&
            tokenActual.isNotEmpty &&
            tokenActual != tokenUsado)
        ? tokenActual
        : await _renovarUnaSolaVez();

    if (nuevoToken == null) {
      handler.next(err);
      return;
    }

    try {
      handler.resolve(await _reintentar(peticion, nuevoToken));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _procedeRenovar(DioException err) {
    if (err.response?.statusCode != 401) return false;
    final extra = err.requestOptions.extra;
    if (extra[OpcionesAuth.claveReintento] == true) return false;
    final esquema =
        extra[OpcionesAuth.claveEsquema] as EsquemaAuth? ?? EsquemaAuth.datos;
    return esquema == EsquemaAuth.datos;
  }

  /// El candado: la primera petición que llega crea el `Completer` y las demás
  /// se cuelgan de él, así que solo sale un `refresh-data` a la red.
  Future<String?> _renovarUnaSolaVez() {
    final enCurso = _refrescoEnCurso;
    if (enCurso != null) return enCurso.future;

    final completer = Completer<String?>();
    _refrescoEnCurso = completer;

    unawaited(
      _ejecutarRefresco().then((token) {
        _refrescoEnCurso = null;
        completer.complete(token);
      }, onError: (Object _, StackTrace _) {
        _refrescoEnCurso = null;
        completer.complete(null);
      }),
    );

    return completer.future;
  }

  Future<String?> _ejecutarRefresco() async {
    try {
      final renovado = await _refrescar();
      await _tokens.guardarDataToken(renovado.token, renovado.expiraEn);
      return renovado.token;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 401 o 410: la sesión venció o fue revocada. 403: cuenta suspendida.
      if (status == 401 || status == 403 || status == 410) {
        await _invalidarSesion(ApiError.deDio(e));
      }
      return null;
    } on Object {
      return null;
    }
  }

  Future<void> _invalidarSesion(ApiError motivo) async {
    await _tokens.limpiarTokens();
    alInvalidarSesion?.call(motivo);
  }

  String? _tokenDeLaPeticion(RequestOptions peticion) {
    final cabecera = peticion.headers['Authorization'];
    if (cabecera is String && cabecera.startsWith('Bearer ')) {
      return cabecera.substring(7);
    }
    return null;
  }

  Future<Response<dynamic>> _reintentar(
    RequestOptions peticion,
    String token,
  ) {
    final cabeceras = Map<String, dynamic>.from(peticion.headers)
      ..['Authorization'] = 'Bearer $token';

    return _dioReintento().request<dynamic>(
      peticion.path,
      data: peticion.data,
      queryParameters: peticion.queryParameters,
      cancelToken: peticion.cancelToken,
      options: Options(
        method: peticion.method,
        headers: cabeceras,
        responseType: peticion.responseType,
        contentType: peticion.contentType,
        sendTimeout: peticion.sendTimeout,
        receiveTimeout: peticion.receiveTimeout,
        validateStatus: peticion.validateStatus,
        extra: Map<String, dynamic>.from(peticion.extra)
          ..[OpcionesAuth.claveReintento] = true,
      ),
    );
  }
}
