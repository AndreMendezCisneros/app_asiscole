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

  /// `DateFormat` (intl) formatea mal un `TZDateTime` (a menudo muestra UTC).
  /// Se pasa un `DateTime` civil con los componentes de Lima.
  static DateTime _civil(DateTime utc) {
    final lima = enLima(utc);
    return DateTime(
      lima.year,
      lima.month,
      lima.day,
      lima.hour,
      lima.minute,
      lima.second,
      lima.millisecond,
      lima.microsecond,
    );
  }

  static String hora(DateTime utc) =>
      DateFormat.Hm(Env.locale).format(_civil(utc));

  static String fechaLarga(DateTime utc) =>
      DateFormat("d 'de' MMMM 'de' y", Env.locale).format(_civil(utc));

  static String horaAmPm(DateTime utc) {
    return DateFormat('h:mm a', Env.locale).format(_civil(utc));
  }

  static String fechaHoraAmPm(DateTime utc) =>
      DateFormat("d 'de' MMMM, h:mm a", Env.locale).format(_civil(utc));

  /// Cuenta regresiva `m:ss`.
  static String cuentaRegresiva(Duration restante) {
    final minutos = restante.inMinutes;
    final segundos = restante.inSeconds % 60;
    return '$minutos:${segundos.toString().padLeft(2, '0')}';
  }
}

/// Interpreta `emitido_en` del API como instante absoluto.
///
/// Si viene sin zona (naive), se asume UTC: el canal / Supabase a veces emite
/// el reloj UTC sin sufijo `Z`, y Dart lo trataría como hora local (+5 h en PE).
///
/// VPS legacy a veces etiqueta el reloj UTC con offset Lima
/// (`18:47:52-05:00` en vez de `18:47:52Z` / `13:47:52-05:00`). Eso deja el
/// instante ~5 h en el futuro; en ese caso se reinterpreta el civil como UTC.
DateTime parseInstanteApi(String crudo) {
  final dt = DateTime.parse(crudo);
  final absoluto = dt.toUtc();
  final ahora = DateTime.now().toUtc();
  if (absoluto.difference(ahora) > const Duration(hours: 2)) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(\.\d+)?',
    ).firstMatch(crudo.trim());
    if (m != null) {
      final frac = m.group(7);
      var ms = 0;
      var us = 0;
      if (frac != null && frac.length > 1) {
        final digits = (frac.substring(1) + '000000').substring(0, 6);
        ms = int.parse(digits.substring(0, 3));
        us = int.parse(digits.substring(3, 6));
      }
      final comoUtc = DateTime.utc(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
        ms,
        us,
      );
      if (comoUtc.difference(ahora).abs() < absoluto.difference(ahora).abs()) {
        return comoUtc;
      }
    }
  }
  if (dt.isUtc) return absoluto;
  return DateTime.utc(
    dt.year,
    dt.month,
    dt.day,
    dt.hour,
    dt.minute,
    dt.second,
    dt.millisecond,
    dt.microsecond,
  );
}
