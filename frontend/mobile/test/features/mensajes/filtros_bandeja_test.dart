import 'package:asiscole_app/features/mensajes/domain/filtros_bandeja.dart';
import 'package:asiscole_app/features/mensajes/domain/mensaje.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Mensaje _mensaje({
  required String tipo,
  Map<String, dynamic> metadata = const {},
}) =>
    Mensaje(
      id: 'm-$tipo-${metadata['contexto'] ?? ''}',
      tipo: tipo,
      texto: 'texto',
      emitidoEn: DateTime.utc(2026, 9, 14, 13),
      metadata: metadata,
    );

void main() {
  setUpAll(() => initializeDateFormatting('es_PE'));

  group('esCitacion', () {
    test('un aviso con contexto cita es citación', () {
      expect(
        esCitacion(_mensaje(tipo: 'aviso', metadata: {'contexto': 'cita'})),
        isTrue,
      );
    });

    test('no distingue mayúsculas ni espacios', () {
      expect(
        esCitacion(_mensaje(tipo: 'aviso', metadata: {'contexto': ' Cita '})),
        isTrue,
      );
    });

    test('un aviso de pensión no es citación', () {
      expect(
        esCitacion(_mensaje(tipo: 'aviso', metadata: {'contexto': 'pension'})),
        isFalse,
      );
    });

    test('un aviso sin contexto no es citación', () {
      expect(esCitacion(_mensaje(tipo: 'aviso')), isFalse);
    });

    test('una incidencia no es citación aunque traiga el contexto', () {
      expect(
        esCitacion(
          _mensaje(tipo: 'incidencia', metadata: {'contexto': 'cita'}),
        ),
        isFalse,
      );
    });
  });

  group('tituloDia', () {
    final hoy = DateTime(2026, 9, 16);

    test('el día de hoy', () {
      expect(tituloDia(hoy, hoy), 'Hoy');
    });

    test('el día anterior', () {
      expect(tituloDia(DateTime(2026, 9, 15), hoy), 'Ayer');
    });

    test('dentro de la semana usa el día y el número', () {
      expect(tituloDia(DateTime(2026, 9, 14), hoy), 'Lunes 14');
    });

    test('más atrás usa la fecha', () {
      expect(tituloDia(DateTime(2026, 8, 30), hoy), '30 de agosto');
    });
  });
}
