import 'package:asiscole_app/core/config/env.dart';
import 'package:asiscole_app/core/version/actualizador_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usa la ficha que manda el servidor', () {
    expect(
      ActualizadorApp.urlTienda(
        esIos: true,
        urlServidor: ' https://apps.apple.com/app/id123 ',
      ),
      'https://apps.apple.com/app/id123',
    );
  });

  test('en iOS sin ficha del servidor no cae a Play', () {
    final url = ActualizadorApp.urlTienda(esIos: true, urlServidor: null);
    expect(url, Env.urlFichaAppStore);
    expect(url, isNot(contains('play.google.com')));
  });

  test('en Android sin ficha del servidor usa Play', () {
    expect(
      ActualizadorApp.urlTienda(esIos: false, urlServidor: ''),
      Env.urlFichaPlay,
    );
  });
}
