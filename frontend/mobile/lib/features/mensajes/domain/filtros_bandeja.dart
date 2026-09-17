import 'package:intl/intl.dart';

import '../../../core/config/env.dart';
import 'mensaje.dart';

/// Criterios de la bandeja, fuera de la pantalla para poder probarlos solos.

/// Una citación no es un tipo propio: el backend la emite como aviso con
/// `metadata.contexto = "cita"` (ver `plantillas/aviso.py`). El cliente ya
/// guarda `metadata`, así que el filtro funciona con lo ya descargado y sin
/// tocar el servidor.
bool esCitacion(Mensaje m) =>
    m.tipo == 'aviso' &&
    '${m.metadata['contexto'] ?? ''}'.trim().toLowerCase() == 'cita';

/// Título del separador de día: «Hoy», «Ayer», «Lunes 14» o «14 de septiembre».
///
/// [dia] y [hoy] son fechas civiles de la zona del colegio, sin hora.
String tituloDia(DateTime dia, DateTime hoy) {
  final diferencia = hoy.difference(dia).inDays;
  if (diferencia == 0) return 'Hoy';
  if (diferencia == 1) return 'Ayer';
  final texto =
      diferencia < 7 ? _fmtDiaSemana.format(dia) : _fmtFechaDia.format(dia);
  return texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);
}

final _fmtDiaSemana = DateFormat('EEEE d', Env.locale);
final _fmtFechaDia = DateFormat("d 'de' MMMM", Env.locale);
