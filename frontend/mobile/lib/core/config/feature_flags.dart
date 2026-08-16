import 'package:flutter/foundation.dart';

import '../network/api_client.dart';

/// Flags remotos del canal (`GET /feature-flags`, RF-H03).
///
/// Se consultan una vez al entrar y quedan en memoria: la barra de navegación y
/// la pantalla de Notas leen el mismo valor, así que no se piden dos veces ni
/// pueden discrepar entre sí.
class FeatureFlags {
  FeatureFlags(this._api);

  final ApiClient _api;

  /// Con el flag apagado la pestaña de Notas no se muestra: una sección que
  /// nunca tiene contenido parece funcionalidad a medias (y Play lo revisa).
  final ValueNotifier<bool> notas = ValueNotifier(false);

  bool _consultado = false;

  Future<void> refrescar({bool forzar = false}) async {
    if (_consultado && !forzar) return;
    try {
      final resp = await _api.dio.get<Map<String, dynamic>>('/feature-flags');
      notas.value = resp.data?['notas'] == true;
      _consultado = true;
    } on Object {
      // Sin red o con error, los módulos opcionales quedan ocultos. Nunca es
      // motivo para bloquear la app: la bandeja de mensajes no depende de esto.
      notas.value = false;
    }
  }
}
