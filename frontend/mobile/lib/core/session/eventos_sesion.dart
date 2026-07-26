import 'dart:async';

import '../error/api_error.dart';

/// Bus mínimo entre la capa de red y el estado de sesión.
///
/// El interceptor no conoce al cubit: cuando la sesión deja de ser válida
/// publica aquí y quien escuche decide a qué pantalla ir.
class EventosSesion {
  final StreamController<ApiError> _controlador =
      StreamController<ApiError>.broadcast();

  Stream<ApiError> get invalidaciones => _controlador.stream;

  void sesionInvalidada(ApiError motivo) {
    if (!_controlador.isClosed) _controlador.add(motivo);
  }

  Future<void> cerrar() => _controlador.close();
}
