import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema elegido por el apoderado, persistido entre arranques.
///
/// El valor por defecto es [ThemeMode.system]: quien tiene el teléfono en
/// oscuro ve la app en oscuro sin tener que buscar el ajuste, y quien nunca
/// tocó nada la sigue viendo igual que hasta ahora.
class PreferenciaTema {
  static const String _clave = 'tema_modo';

  final ValueNotifier<ThemeMode> modo = ValueNotifier(ThemeMode.system);

  bool _restaurado = false;

  /// Lee el disco una sola vez. Si falla, se queda en automático.
  Future<void> cargar() async {
    if (_restaurado) return;
    _restaurado = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      modo.value = _desdeTexto(prefs.getString(_clave));
    } on Object {
      // Primera instalación o almacén inaccesible.
    }
  }

  Future<void> cambiar(ThemeMode nuevo) async {
    if (modo.value == nuevo) return;
    modo.value = nuevo;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave, nuevo.name);
    } on Object {
      // El cambio ya se aplicó en pantalla; solo no sobrevive al cierre.
    }
  }

  static ThemeMode _desdeTexto(String? valor) => switch (valor) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
