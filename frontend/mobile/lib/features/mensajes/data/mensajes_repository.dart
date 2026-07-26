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
    // No usamos `since`: con el desfase TZ de la BD central el filtro
    // `emitido_en__gt` puede ocultar mensajes posteriores (p. ej. la salida).
    // Traemos la bandeja reciente y hacemos upsert por id.
    final pagina = await _api.listar();
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
