import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:asiscole_app/core/error/api_error.dart';
import 'package:asiscole_app/core/error/error_codes.dart';
import 'package:asiscole_app/core/network/auth_interceptor.dart';
import 'package:asiscole_app/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Almacén de tokens en memoria.
class TokenStoreFalso implements TokenStore {
  TokenStoreFalso({this.sessionToken = 'session-1', this.dataToken = 'data-1'});

  String? sessionToken;
  String? dataToken;
  int vecesLimpiado = 0;

  @override
  Future<String?> leerSessionToken() async => sessionToken;

  @override
  Future<String?> leerDataToken() async => dataToken;

  @override
  Future<void> guardarDataToken(String token, DateTime? expiraEn) async {
    dataToken = token;
  }

  @override
  Future<void> limpiarTokens() async {
    vecesLimpiado++;
    sessionToken = null;
    dataToken = null;
  }
}

/// Adaptador HTTP controlado por el test.
class AdaptadorFalso implements HttpClientAdapter {
  AdaptadorFalso(this.responder);

  final Future<ResponseBody> Function(RequestOptions opciones) responder;
  final List<RequestOptions> peticiones = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    peticiones.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, Object?> cuerpo, int estado) =>
    ResponseBody.fromString(
      jsonEncode(cuerpo),
      estado,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

String? _tokenDe(RequestOptions opciones) {
  final cabecera = opciones.headers['Authorization'];
  return cabecera is String ? cabecera.replaceFirst('Bearer ', '') : null;
}

void main() {
  group('AuthInterceptor', () {
    late TokenStoreFalso tokens;
    late Dio dio;
    late AdaptadorFalso adaptador;

    Dio construir({
      required RefrescarDatos refrescar,
      required Future<ResponseBody> Function(RequestOptions) responder,
      void Function(ApiError)? alInvalidar,
    }) {
      final cliente = Dio(BaseOptions(baseUrl: 'https://pruebas.asiscole.pe'));
      adaptador = AdaptadorFalso(responder);
      cliente.httpClientAdapter = adaptador;
      cliente.interceptors.add(
        AuthInterceptor(
          tokens: tokens,
          refrescar: refrescar,
          dioReintento: () => cliente,
          alInvalidarSesion: alInvalidar,
        ),
      );
      return cliente;
    }

    setUp(() => tokens = TokenStoreFalso());

    test(
      'varias peticiones con 401 disparan un solo refresh y se reintentan',
      () async {
        var refrescos = 0;

        Future<DataTokenRenovado> refrescar() async {
          refrescos++;
          // El retardo garantiza que las demás peticiones lleguen mientras
          // el refresco sigue en vuelo.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return (token: 'data-2', expiraEn: DateTime.now().toUtc());
        }

        dio = construir(
          refrescar: refrescar,
          responder: (opciones) async {
            if (_tokenDe(opciones) == 'data-1') {
              return _json({'code': CodigosError.noAutenticado}, 401);
            }
            return _json({'ok': true}, 200);
          },
        );

        final respuestas = await Future.wait([
          dio.get<dynamic>('/mensajes'),
          dio.get<dynamic>('/asistencias'),
          dio.get<dynamic>('/incidencias'),
          dio.get<dynamic>('/perfil'),
          dio.get<dynamic>('/feature-flags'),
        ]);

        expect(refrescos, 1, reason: 'el candado debe dejar pasar un refresco');
        expect(respuestas.map((r) => r.statusCode), everyElement(200));
        expect(tokens.dataToken, 'data-2');
        // 5 fallidas + 5 reintentos: ninguna se reintenta dos veces.
        expect(adaptador.peticiones.length, 10);
      },
    );

    test('el 401 de un reintento ya no vuelve a refrescar', () async {
      var refrescos = 0;

      dio = construir(
        refrescar: () async {
          refrescos++;
          return (token: 'data-2', expiraEn: null);
        },
        responder: (_) async => _json({'code': CodigosError.noAutenticado}, 401),
      );

      await expectLater(
        dio.get<dynamic>('/mensajes'),
        throwsA(isA<DioException>()),
      );
      expect(refrescos, 1);
      expect(adaptador.peticiones.length, 2);
    });

    test('un 410 al refrescar borra los tokens y avisa de la sesión muerta',
        () async {
      ApiError? motivo;

      dio = construir(
        refrescar: () async => throw DioException(
          requestOptions: RequestOptions(path: '/auth/refresh-data'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/auth/refresh-data'),
            statusCode: 410,
            data: {
              'code': CodigosError.sesionExpirada,
              'message': 'La sesión venció.',
            },
          ),
        ),
        responder: (_) async => _json({'code': CodigosError.noAutenticado}, 401),
        alInvalidar: (e) => motivo = e,
      );

      await expectLater(
        dio.get<dynamic>('/mensajes'),
        throwsA(isA<DioException>()),
      );
      expect(tokens.vecesLimpiado, 1);
      expect(tokens.sessionToken, isNull);
      expect(motivo?.codigo, CodigosError.sesionExpirada);
    });

    test('el esquema de sesión no dispara refresco', () async {
      var refrescos = 0;

      dio = construir(
        refrescar: () async {
          refrescos++;
          return (token: 'data-2', expiraEn: null);
        },
        responder: (_) async => _json({'code': CodigosError.noAutenticado}, 401),
      );

      await expectLater(
        dio.post<dynamic>(
          '/auth/refresh-data',
          options: OpcionesAuth.con(EsquemaAuth.sesion),
        ),
        throwsA(isA<DioException>()),
      );
      expect(refrescos, 0);
      expect(adaptador.peticiones.single.headers['Authorization'],
          'Bearer session-1');
    });

    test('cada esquema envía el token que le toca', () async {
      dio = construir(
        refrescar: () async => (token: 'data-2', expiraEn: null),
        responder: (_) async => _json({'ok': true}, 200),
      );

      await dio.post<dynamic>(
        '/auth/login',
        options: OpcionesAuth.con(EsquemaAuth.ninguno),
      );
      await dio.get<dynamic>('/mensajes');

      expect(adaptador.peticiones[0].headers.containsKey('Authorization'), isFalse);
      expect(adaptador.peticiones[1].headers['Authorization'], 'Bearer data-1');
    });
  });
}
