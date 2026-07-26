import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../config/env.dart';

/// Teléfono peruano: 9 dígitos, mostrados como `987 654 321`.
class TelefonoPeru {
  const TelefonoPeru._();

  static const String prefijo = '+51';
  static const int digitos = 9;

  static String soloDigitos(String valor) =>
      valor.replaceAll(RegExp(r'\D'), '');

  static bool esValido(String valor) {
    final limpio = soloDigitos(valor);
    return limpio.length == digitos && limpio.startsWith('9');
  }

  /// Formato E.164 que exige el contrato: `+51987654321`.
  static String aE164(String valor) => '$prefijo${soloDigitos(valor)}';

  static String legible(String valor) {
    final d = soloDigitos(valor);
    final partes = <String>[
      if (d.length > 3) d.substring(0, 3) else d,
      if (d.length > 3) (d.length > 6 ? d.substring(3, 6) : d.substring(3)),
      if (d.length > 6) d.substring(6),
    ];
    return partes.where((p) => p.isNotEmpty).join(' ');
  }
}

/// Agrupa los dígitos mientras se escribe y corta a nueve.
class FormateadorTelefonoPeru extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    var d = TelefonoPeru.soloDigitos(nuevo.text);
    if (d.length > TelefonoPeru.digitos) {
      d = d.substring(0, TelefonoPeru.digitos);
    }
    final texto = TelefonoPeru.legible(d);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Fechas y horas siempre en la zona del colegio (America/Lima).
class FechasLima {
  const FechasLima._();

  static tz.Location get _lima => tz.getLocation(Env.zonaHoraria);

  static DateTime enLima(DateTime utc) =>
      tz.TZDateTime.from(utc.toUtc(), _lima);

  static String hora(DateTime utc) =>
      DateFormat.Hm(Env.locale).format(enLima(utc));

  static String fechaLarga(DateTime utc) =>
      DateFormat("d 'de' MMMM 'de' y", Env.locale).format(enLima(utc));

  static String fechaHora(DateTime utc) =>
      DateFormat("d MMM y, HH:mm", Env.locale).format(enLima(utc));

  /// Cuenta regresiva `m:ss`.
  static String cuentaRegresiva(Duration restante) {
    final minutos = restante.inMinutes;
    final segundos = restante.inSeconds % 60;
    return '$minutos:${segundos.toString().padLeft(2, '0')}';
  }
}
