import 'package:asiscole_app/core/version/version_app_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PoliticaVersion.fromJson lee el contrato', () {
    final p = PoliticaVersion.fromJson({
      'plataforma': 'android',
      'min_soportada': 1,
      'ultima_disponible': 2,
      'actualizacion_obligatoria': false,
      'actualizacion_disponible': true,
      'mensaje': 'Hay una versión nueva',
      'url_tienda': 'https://play.google.com/store',
    });
    expect(p.minSoportada, 1);
    expect(p.ultimaDisponible, 2);
    expect(p.actualizacionObligatoria, isFalse);
    expect(p.actualizacionDisponible, isTrue);
    expect(p.mensaje, contains('versión'));
  });

  test('PoliticaVersion.fromJson no bloquea si faltan booleanos', () {
    final p = PoliticaVersion.fromJson({'min_soportada': 3});
    expect(p.minSoportada, 3);
    expect(p.actualizacionObligatoria, isFalse);
  });
}
