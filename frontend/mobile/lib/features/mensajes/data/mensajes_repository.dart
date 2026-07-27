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

  Future<List<Mensaje>> sincronizar() async {
    final online = await _red.hayConexion;
    if (!online) {
      return _desdeCache();
    }
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
    final pagina = await _api.listar(since: since);
    await _local.guardarMensajes(
      pagina.items.map((m) => m.toLocalRow()).toList(),
    );
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
      await _api.marcarLeidos(ids);
    }
  }
}
