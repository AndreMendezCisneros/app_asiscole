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

  Future<void> cargar() async {
    emit(MensajesCargando());
    try {
      final items = await _repo.sincronizar();
      emit(MensajesListos(items));
    } catch (_) {
      try {
        final cache = await _repo.soloCache();
        emit(MensajesListos(cache, offline: true));
      } catch (e) {
        emit(MensajesError('No se pudieron cargar los mensajes.'));
      }
    }
  }

  Future<void> abrir(Mensaje mensaje) async {
    if (!mensaje.leido) {
      await _repo.marcarLeidos([mensaje.id]);
      await cargar();
    }
  }
}
