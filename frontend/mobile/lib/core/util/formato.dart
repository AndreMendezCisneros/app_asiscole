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

  // DateFormat es caro de construir; se reutiliza en listas/scroll.
  static DateFormat? _fmtHm;
  static DateFormat? _fmtFechaLarga;
  static DateFormat? _fmtHoraAmPm;
  static DateFormat? _fmtFechaHoraAmPm;
  static DateFormat? _fmtDiaMesCorto;

  static DateFormat get _hm => _fmtHm ??= DateFormat.Hm(Env.locale);
  static DateFormat get _fechaLarga =>
      _fmtFechaLarga ??= DateFormat("d 'de' MMMM 'de' y", Env.locale);
  static DateFormat get _horaAmPmFmt =>
      _fmtHoraAmPm ??= DateFormat('h:mm a', Env.locale);
  static DateFormat get _fechaHoraAmPmFmt =>
      _fmtFechaHoraAmPm ??= DateFormat("d 'de' MMMM, h:mm a", Env.locale);
  static DateFormat get diaMesCorto =>
      _fmtDiaMesCorto ??= DateFormat('d MMM', Env.locale);

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

  static String hora(DateTime utc) => _hm.format(_civil(utc));

  static String fechaLarga(DateTime utc) => _fechaLarga.format(_civil(utc));

  static String horaAmPm(DateTime utc) => _horaAmPmFmt.format(_civil(utc));

  static String fechaHoraAmPm(DateTime utc) =>
      _fechaHoraAmPmFmt.format(_civil(utc));

  /// Cuenta regresiva `m:ss`.
  static String cuentaRegresiva(Duration restante) {
    final minutos = restante.inMinutes;
    final segundos = restante.inSeconds % 60;
    return '$minutos:${segundos.toString().padLeft(2, '0')}';
  }
}

/// Zona explícita al final de un ISO-8601: `Z`, `+05:00`, `-0500`.
final RegExp _zonaExplicita = RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

/// Interpreta `emitido_en` del API como instante absoluto.
///
/// El canal siempre emite UTC con sufijo `Z` (`_emitido_iso` en el backend), así
/// que basta con respetar la zona que venga en el texto. Sin zona (naive) se
/// asume UTC: Dart lo tomaría como hora local del teléfono, que en Perú
/// adelantaría el mensaje cinco horas.
///
/// A propósito no hay heurística que compare con el reloj del dispositivo: haría
/// que el mismo `emitido_en` se mostrara distinto según cuándo se lea.
DateTime parseInstanteApi(String crudo) {
  final texto = crudo.trim();
  final dt = DateTime.parse(texto);
  if (_zonaExplicita.hasMatch(texto)) return dt.toUtc();
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
