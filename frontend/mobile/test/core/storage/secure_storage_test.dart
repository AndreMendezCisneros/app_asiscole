import 'package:asiscole_app/core/storage/secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AlmacenFalso extends Mock implements FlutterSecureStorage {}

void main() {
  late _AlmacenFalso almacen;
  late SecureStorage storage;

  setUp(() {
    almacen = _AlmacenFalso();
    when(() => almacen.deleteAll()).thenAnswer((_) async {});
    storage = SecureStorage(almacen);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('en iOS la primera ejecución borra el Keychain heredado', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await storage.olvidarSiEsInstalacionNueva();
    await storage.olvidarSiEsInstalacionNueva();

    verify(() => almacen.deleteAll()).called(1);
  });

  test('en Android no toca la sesión al actualizar la app', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await storage.olvidarSiEsInstalacionNueva();

    verifyNever(() => almacen.deleteAll());
  });
}
