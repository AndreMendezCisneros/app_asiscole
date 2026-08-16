@TestOn('vm')
library;

import 'package:asiscole_app/core/storage/local_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fila mínima tal como la deja `Mensaje.toLocalRow`.
Map<String, Object?> _fila(String id) => {
      'id': id,
      'tipo': 'entrada',
      'texto': 'Estudiante Prueba ingresó al colegio.',
      'colegio': 'Jean Piaget',
      'estudiante_id': 11,
      'estudiante_nombre': 'Estudiante Prueba',
      'emitido_en': '2026-07-27T12:30:00.000Z',
      'entregado': true,
      'leido': false,
      'metadata': {'grado': '3', 'seccion': 'A'},
    };

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalDb db;
  var contador = 0;

  setUp(() async {
    db = LocalDb(nombreArchivo: 'prueba_${contador++}.db');
    await db.vaciar();
  });

  tearDown(() => db.cerrar());

  test('vaciar borra los mensajes cacheados y la cola de leídos', () async {
    await db.guardarMensajes([_fila('a'), _fila('b')]);
    await db.encolarLeidosPendientes(['a']);
    expect((await db.mensajes()).length, 2);
    expect(await db.leidosPendientes(), ['a']);

    await db.vaciar();

    // La caché guarda el nombre del estudiante y el texto del aviso: al cerrar
    // sesión o eliminar la cuenta no debe quedar nada (Ley N.º 29733).
    expect(await db.mensajes(), isEmpty);
    expect(await db.leidosPendientes(), isEmpty);
    expect(await db.ultimaMarcaDeTiempo(), isNull);
  });

  test('vaciar deja la base usable para la siguiente sesión', () async {
    await db.guardarMensajes([_fila('a')]);
    await db.vaciar();
    await db.guardarMensajes([_fila('c')]);
    expect((await db.mensajes()).single['id'], 'c');
  });

  test('marcarLeidos solo toca los ids indicados', () async {
    await db.guardarMensajes([_fila('a'), _fila('b')]);
    await db.marcarLeidos(['a']);
    final filas = await db.mensajes();
    final leidos = {for (final f in filas) f['id'] as String: f['leido']};
    expect(leidos['a'], 1);
    expect(leidos['b'], 0);
  });
}
