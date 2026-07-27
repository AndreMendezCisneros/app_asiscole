import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/mensajes_repository.dart';
import '../domain/mensaje.dart';

sealed class MensajesState {}

class MensajesCargando extends MensajesState {}

class MensajesListos extends MensajesState {
  MensajesListos(this.items, {this.offline = false});
  final List<Mensaje> items;
  final bool offline;
}

class MensajesError extends MensajesState {
  MensajesError(this.mensaje);
  final String mensaje;
}

class MensajesCubit extends Cubit<MensajesState> {
  MensajesCubit(this._repo) : super(MensajesCargando());

  final MensajesRepository _repo;

  Future<void> cargar({bool silencioso = false}) async {
    final habiaLista = state is MensajesListos;
    if (!habiaLista) {
      try {
        final cache = await _repo.soloCache();
        if (cache.isNotEmpty) {
          emit(MensajesListos(cache));
        } else if (!silencioso) {
          emit(MensajesCargando());
        }
      } catch (_) {
        if (!silencioso) emit(MensajesCargando());
      }
    }
    try {
      final items = await _repo.sincronizar();
      emit(MensajesListos(items));
    } catch (_) {
      try {
        final cache = await _repo.soloCache();
        emit(MensajesListos(cache, offline: true));
      } catch (e) {
        if (state is! MensajesListos) {
          emit(MensajesError('No se pudieron cargar los mensajes.'));
        }
      }
    }
  }

  /// Marca leído en UI al instante; persiste en background sin spinner.
  Future<void> abrir(Mensaje mensaje) async {
    if (mensaje.leido) return;

    final actual = state;
    if (actual is MensajesListos) {
      emit(
        MensajesListos(
          [
            for (final m in actual.items)
              if (m.id == mensaje.id) m.copyWith(leido: true) else m,
          ],
          offline: actual.offline,
        ),
      );
    }

    try {
      await _repo.marcarLeidos([mensaje.id]);
    } on Object {
      // La UI ya mostró leído; un pull-to-refresh sincroniza si falló la red.
    }
  }
}
