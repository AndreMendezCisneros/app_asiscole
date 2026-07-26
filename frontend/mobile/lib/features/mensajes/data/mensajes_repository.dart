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
      final cache = await _local.mensajes();
      return cache.map(Mensaje.fromLocal).toList();
    }
    final since = await _local.ultimaMarcaDeTiempo();
    final pagina = await _api.listar(since: since);
    await _local.guardarMensajes(
      pagina.items.map((m) => m.toLocalRow()).toList(),
    );
    final todos = await _local.mensajes();
    return todos.map(Mensaje.fromLocal).toList();
  }

  Future<void> marcarLeidos(List<String> ids) async {
    await _local.marcarLeidos(ids);
    if (await _red.hayConexion) {
      await _api.marcarLeidos(ids);
    }
  }
}
