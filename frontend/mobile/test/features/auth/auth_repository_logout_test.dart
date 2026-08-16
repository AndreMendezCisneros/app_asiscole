import 'package:asiscole_app/core/device/info_dispositivo.dart';
import 'package:asiscole_app/features/auth/data/auth_api.dart';
import 'package:asiscole_app/features/auth/data/auth_repository.dart';
import 'package:asiscole_app/features/auth/data/session_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class AuthApiMock extends Mock implements AuthApi {}

class SessionStorageMock extends Mock implements SessionStorage {}

class InfoDispositivoMock extends Mock implements InfoDispositivo {}

void main() {
  late AuthApiMock api;
  late SessionStorageMock almacen;
  var cacheBorrada = 0;

  setUp(() {
    api = AuthApiMock();
    almacen = SessionStorageMock();
    cacheBorrada = 0;
    when(almacen.limpiarTokens).thenAnswer((_) async {});
  });

  AuthRepository crear() => AuthRepository(
        api: api,
        almacen: almacen,
        dispositivo: InfoDispositivoMock(),
        borrarCacheMensajes: () async => cacheBorrada++,
      );

  test('cerrar sesión borra tokens y caché de mensajes', () async {
    when(api.logout).thenAnswer((_) async {});

    await crear().cerrarSesion();

    verify(almacen.limpiarTokens).called(1);
    // La caché guarda nombres de menores: no sobrevive al cierre de sesión.
    expect(cacheBorrada, 1);
  });

  test('si el logout del backend falla, la caché se borra igual', () async {
    when(api.logout).thenThrow(
      DioException(requestOptions: RequestOptions(path: '/auth/logout')),
    );

    await crear().cerrarSesion();

    verify(almacen.limpiarTokens).called(1);
    expect(cacheBorrada, 1);
  });

  test('un fallo al borrar la caché no impide cerrar sesión', () async {
    when(api.logout).thenAnswer((_) async {});
    final repo = AuthRepository(
      api: api,
      almacen: almacen,
      dispositivo: InfoDispositivoMock(),
      borrarCacheMensajes: () async => throw Exception('base local bloqueada'),
    );

    await repo.cerrarSesion();

    verify(almacen.limpiarTokens).called(1);
  });
}
