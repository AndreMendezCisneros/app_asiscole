import 'package:asiscole_app/features/incidencias/data/incidencias_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IncidenciaResumen.fromJson', () {
    test('lee las observaciones del auxiliar', () {
      final item = IncidenciaResumen.fromJson({
        'id': 1,
        'fecha': '2026-09-14T08:12:00-05:00',
        'categoria': 'Leve',
        'falta': 'Tardanza',
        'es_grave': false,
        'reportado_por': 'Auxiliar',
        'observaciones': '  Llegó 20 minutos tarde  ',
      });

      expect(item.observaciones, 'Llegó 20 minutos tarde');
    });

    test('un backend sin la clave no rompe el listado', () {
      final item = IncidenciaResumen.fromJson({
        'id': 2,
        'fecha': '2026-09-14T08:12:00-05:00',
        'categoria': 'Leve',
        'falta': 'Tardanza',
        'es_grave': false,
        'reportado_por': 'Auxiliar',
      });

      expect(item.observaciones, isEmpty);
    });

    test('confirmar conserva las observaciones', () {
      final item = IncidenciaResumen.fromJson({
        'id': 3,
        'fecha': '2026-09-14T08:12:00-05:00',
        'categoria': 'Grave',
        'falta': 'Agresión verbal',
        'es_grave': true,
        'reportado_por': 'Auxiliar',
        'observaciones': 'Se conversó con el estudiante',
      }).copyWith(confirmada: true);

      expect(item.observaciones, 'Se conversó con el estudiante');
      expect(item.confirmada, isTrue);
    });
  });
}
