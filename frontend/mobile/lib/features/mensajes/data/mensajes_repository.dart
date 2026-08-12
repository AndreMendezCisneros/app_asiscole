import '../../../core/connectivity/network_info.dart';
import '../../../core/storage/local_db.dart';
import '../domain/mensaje.dart';
import 'mensajes_api.dart';

class MensajesRepository {
  MensajesRepository({
    required MensajesApi api,
    required LocalDb local,
    required NetworkInfo red,
  })  : _api = api,
        _local = local,
        _red = red;

  final MensajesApi _api;
  final LocalDb _local;
  final NetworkInfo _red;

  static const int _maxPaginasSync = 5;

  Future<List<Mensaje>> sincronizar() async {
    // No cortar por connectivity_plus: en MIUI a veces marca “sin red” con
    // datos activos. Si la API falla, el cubit cae a caché.
    await _flushLeidosPendientes();

    // `since` con margen de 6 h: evita perder mensajes por desfase TZ de la BD
    // central, y reduce el payload cuando ya hay caché local.
    String? since;
    final ultima = await _local.ultimaMarcaDeTiempo();
    if (ultima != null) {
      final dt = DateTime.tryParse(ultima);
      if (dt != null) {
        since = dt
            .toUtc()
            .subtract(const Duration(hours: 6))
            .toIso8601String();
      }
    }

    String? cursor;
    for (var i = 0; i < _maxPaginasSync; i++) {
      final pagina = await _api.listar(since: since, cursor: cursor);
      await _local.guardarMensajes(
        pagina.items.map((m) => m.toLocalRow()).toList(),
      );
      cursor = pagina.nextCursor;
      if (cursor == null || cursor.isEmpty || pagina.items.isEmpty) break;
      // Tras la primera página, paginar solo con cursor (sin since).
      since = null;
    }
    return _desdeCache();
  }

  Future<List<Mensaje>> _desdeCache() async {
    final cache = await _local.mensajes();
    return cache.map(Mensaje.fromLocal).toList();
  }

  /// Solo lectura local (sin red). Usado cuando falla la sincronización.
  Future<List<Mensaje>> soloCache() => _desdeCache();

  Future<void> marcarLeidos(List<String> ids) async {
    await _local.marcarLeidos(ids);
    if (await _red.hayConexion) {
      try {
        await _api.marcarLeidos(ids);
        return;
      } on Object {
        await _local.encolarLeidosPendientes(ids);
        return;
      }
    }
    await _local.encolarLeidosPendientes(ids);
  }

  Future<void> _flushLeidosPendientes() async {
    final pendientes = await _local.leidosPendientes();
    if (pendientes.isEmpty) return;
    try {
      await _api.marcarLeidos(pendientes);
      await _local.quitarLeidosPendientes(pendientes);
    } on Object {
      // Se reintentará en el próximo sync.
    }
  }
}
