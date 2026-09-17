import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

/// Flags remotos del canal (`GET /feature-flags`, RF-H03).
///
/// Se consultan una vez al entrar y quedan en memoria: la barra de navegación y
/// la pantalla de Notas leen el mismo valor, así que no se piden dos veces ni
/// pueden discrepar entre sí.
///
/// El último valor conocido se guarda en disco. Sin eso, un fallo de red apagaba
/// los flags y la pestaña de Notas desaparecía del menú: el apoderado no ve una
/// sección deshabilitada, ve que la app perdió una sección.
class FeatureFlags {
  FeatureFlags(this._api);

  final ApiClient _api;

  static const String _claveNotas = 'flag_notas';
  static const String _claveCitacion = 'flag_citacion';

  /// Con el flag apagado la pestaña de Notas se muestra deshabilitada: una
  /// sección que nunca tiene contenido parece funcionalidad a medias (y Play lo
  /// revisa), pero hacerla desaparecer confunde más.
  final ValueNotifier<bool> notas = ValueNotifier(false);

  /// Citaciones (avisos con contexto `cita`). Lo leen Incidencias y la bandeja.
  final ValueNotifier<bool> citacion = ValueNotifier(false);

  bool _consultado = false;
  bool _restaurado = false;

  Future<void> refrescar({bool forzar = false}) async {
    if (_consultado && !forzar) return;
    await _restaurarUnaVez();
    try {
      final resp = await _api.dio.get<Map<String, dynamic>>('/feature-flags');
      notas.value = resp.data?['notas'] == true;
      citacion.value = resp.data?['citacion'] == true;
      _consultado = true;
      await _guardar();
    } on Object {
      // Sin red se conserva lo último que dijo el backend. Nunca es motivo para
      // bloquear la app: la bandeja de mensajes no depende de esto.
    }
  }

  Future<void> _restaurarUnaVez() async {
    if (_restaurado) return;
    _restaurado = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      notas.value = prefs.getBool(_claveNotas) ?? false;
      citacion.value = prefs.getBool(_claveCitacion) ?? false;
    } on Object {
      // Primera instalación o almacén inaccesible: quedan apagados.
    }
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_claveNotas, notas.value);
      await prefs.setBool(_claveCitacion, citacion.value);
    } on Object {
      // Si no se pudo guardar, el próximo arranque los vuelve a pedir.
    }
  }
}
