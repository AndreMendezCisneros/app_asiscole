import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:asiscole_app/core/util/formato.dart';

void main() {
  setUpAll(() async {
    tz_data.initializeTimeZones();
    await initializeDateFormatting('es_PE');
  });

  test('horaAmPm muestra Lima no UTC (+5)', () {
    // 18:33 UTC = 13:33 America/Lima
    final utc = DateTime.utc(2026, 7, 27, 18, 33);
    final marca = FechasLima.horaAmPm(utc);
    expect(marca.toLowerCase(), contains('1:33'));
    expect(marca.toLowerCase(), isNot(contains('6:33')));
  });

  test('parseInstanteApi trata naive como UTC', () {
    final dt = parseInstanteApi('2026-07-27T18:33:00');
    expect(dt.isUtc, isTrue);
    expect(dt.hour, 18);
    expect(FechasLima.horaAmPm(dt).toLowerCase(), contains('1:33'));
  });

  test('parseInstanteApi corrige UTC etiquetado como Lima (-05)', () {
    // VPS legacy: 18:47 UTC con offset -05 → absoluto 23:47 (futuro).
    // Debe reinterpretarse como 18:47Z = 13:47 Lima.
    final dt = parseInstanteApi('2026-07-27T18:47:52.185087-05:00');
    expect(dt.isUtc, isTrue);
    expect(dt.hour, 18);
    expect(FechasLima.horaAmPm(dt).toLowerCase(), contains('1:47'));
  });

  test('parseInstanteApi respeta Lima correcto (-05)', () {
    final dt = parseInstanteApi('2026-07-27T13:47:52.185087-05:00');
    expect(dt.toUtc().hour, 18);
    expect(FechasLima.horaAmPm(dt).toLowerCase(), contains('1:47'));
  });
}
