import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local del dispositivo.
///
/// Solo cachea los mensajes ya recibidos, que es lo único que la app puede
/// mostrar sin conexión. Asistencias, incidencias y perfil no se replican.
class LocalDb {
  LocalDb({String nombreArchivo = 'asiscole.db'})
      : _nombreArchivo = nombreArchivo;

  static const int _version = 6;
  static const String tablaMensajes = 'mensajes';
  static const String tablaLeidosPendientes = 'leidos_pendientes';

  final String _nombreArchivo;
  Database? _db;

  Future<Database> get database async => _db ??= await _abrir();

  Future<Database> _abrir() async {
    final ruta = p.join(await getDatabasesPath(), _nombreArchivo);
    return openDatabase(
      ruta,
      version: _version,
      onCreate: _crear,
      onUpgrade: _actualizar,
    );
  }

  Future<void> _crear(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tablaMensajes (
        id TEXT PRIMARY KEY,
        tipo TEXT NOT NULL,
        texto TEXT NOT NULL,
        colegio TEXT,
        estudiante_id INTEGER,
        estudiante_nombre TEXT,
        emitido_en TEXT NOT NULL,
        entregado INTEGER NOT NULL DEFAULT 0,
        leido INTEGER NOT NULL DEFAULT 0,
        metadata TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_mensajes_emitido_en ON $tablaMensajes (emitido_en DESC)',
    );
    await db.execute('''
      CREATE TABLE $tablaLeidosPendientes (
        id TEXT PRIMARY KEY
      )
    ''');
  }

  /// v2–v5: vaciar caché tras correcciones de `emitido_en` (UTC canónico).
  /// v6: cola de leídos pendientes de reenviar al API.
  Future<void> _actualizar(Database db, int anterior, int nueva) async {
    if (anterior < 5) {
      await db.delete(tablaMensajes);
    }
    if (anterior < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tablaLeidosPendientes (
          id TEXT PRIMARY KEY
        )
      ''');
    }
  }

  /// Inserta o actualiza mensajes ya renderizados por el backend.
  Future<void> guardarMensajes(List<Map<String, Object?>> mensajes) async {
    if (mensajes.isEmpty) return;
    final db = await database;
    final lote = db.batch();
    for (final mensaje in mensajes) {
      lote.insert(
        tablaMensajes,
        {
          'id': mensaje['id'],
          'tipo': mensaje['tipo'],
          'texto': mensaje['texto'],
          'colegio': mensaje['colegio'],
          'estudiante_id': mensaje['estudiante_id'],
          'estudiante_nombre': mensaje['estudiante_nombre'],
          'emitido_en': mensaje['emitido_en'],
          'entregado': (mensaje['entregado'] == true) ? 1 : 0,
          'leido': (mensaje['leido'] == true) ? 1 : 0,
          'metadata':
              mensaje['metadata'] == null ? null : jsonEncode(mensaje['metadata']),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await lote.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> mensajes({int limite = 200}) async {
    final db = await database;
    return db.query(tablaMensajes, orderBy: 'emitido_en DESC', limit: limite);
  }

  /// Marca de tiempo del mensaje más reciente, para la sincronización con `since`.
  Future<String?> ultimaMarcaDeTiempo() async {
    final db = await database;
    final filas = await db.rawQuery(
      'SELECT MAX(emitido_en) AS ultima FROM $tablaMensajes',
    );
    return filas.first['ultima'] as String?;
  }

  Future<void> marcarLeidos(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final marcadores = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $tablaMensajes SET leido = 1 WHERE id IN ($marcadores)',
      ids,
    );
  }

  Future<void> encolarLeidosPendientes(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final lote = db.batch();
    for (final id in ids) {
      lote.insert(
        tablaLeidosPendientes,
        {'id': id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await lote.commit(noResult: true);
  }

  Future<List<String>> leidosPendientes() async {
    final db = await database;
    final filas = await db.query(tablaLeidosPendientes);
    return filas.map((f) => f['id']! as String).toList();
  }

  Future<void> quitarLeidosPendientes(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final marcadores = List.filled(ids.length, '?').join(',');
    await db.rawDelete(
      'DELETE FROM $tablaLeidosPendientes WHERE id IN ($marcadores)',
      ids,
    );
  }

  /// La caché la borra el apoderado; el cierre de sesión no la toca.
  Future<void> vaciar() async {
    final db = await database;
    await db.delete(tablaMensajes);
    await db.delete(tablaLeidosPendientes);
  }

  Future<void> cerrar() async {
    await _db?.close();
    _db = null;
  }
}
