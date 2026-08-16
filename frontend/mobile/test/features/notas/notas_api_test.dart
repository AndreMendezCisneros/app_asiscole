import 'package:flutter_test/flutter_test.dart';

import 'package:asiscole_app/features/notas/data/notas_api.dart';

void main() {
  test('NotaSemanal.fromJson arma semana, rango y nota', () {
    final nota = NotaSemanal.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'id_registro': 991,
      'semana_codigo': '2026-02',
      'semana_etiqueta': 'Semana 2',
      'fecha_inicio': '2026-02-03',
      'fecha_fin': '2026-02-09',
      'nota': '18.5',
      'nota_maxima': '20',
      'area_nombre': 'Ciencias de la Salud',
      'carrera': 'Medicina Humana',
    });
    expect(nota.tituloSemana, 'Semana 2');
    expect(nota.rangoFechas, 'Del 3 de febrero de 2026 al 9 de febrero de 2026');
    expect(nota.notaFormateada, '18.5 / 20');
    expect(nota.carrera, 'Medicina Humana');
    expect(nota.areaNombre, 'Ciencias de la Salud');
  });
}
