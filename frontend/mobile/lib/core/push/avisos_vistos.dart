import 'package:shared_preferences/shared_preferences.dart';

/// Registro de los avisos ya pintados en la bandeja del sistema.
///
/// El backend manda `message_id` justo para esto: FCM puede reintentar la
/// entrega cuando el teléfono estaba dormido, y el mismo aviso aparecía otra
/// vez horas después. Se guarda en `SharedPreferences` y no en SQLite porque el
/// isolate de background también tiene que poder consultarlo.
class AvisosVistos {
  const AvisosVistos._();

  static const String _clave = 'push_vistos_v1';

  /// Tope de ids guardados. Un apoderado con varios hijos recibe unos pocos
  /// avisos al día, así que 200 cubre de sobra la ventana de un día.
  static const int _maximo = 200;

  /// Más allá de esta ventana el id se olvida: si el colegio reenvía algo tan
  /// viejo, es mejor mostrarlo que silenciarlo.
  static const Duration ventana = Duration(hours: 24);

  /// Anota el aviso y devuelve `true` si ya se había mostrado antes.
  ///
  /// Un `messageId` vacío nunca se considera repetido: sin identificador no hay
  /// forma de saberlo y dejar al apoderado sin el aviso es peor que repetirlo.
  static Future<bool> yaMostrado(String messageId) async {
    if (messageId.isEmpty) return false;

    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Object {
      return false;
    }

    final ahora = DateTime.now().millisecondsSinceEpoch;
    final guardados = prefs.getStringList(_clave) ?? const <String>[];
    final vigentes = <String>[];
    var repetido = false;

    for (final linea in guardados) {
      final corte = linea.lastIndexOf('|');
      if (corte <= 0) continue;
      final marca = int.tryParse(linea.substring(corte + 1));
      if (marca == null || ahora - marca > ventana.inMilliseconds) continue;
      if (linea.substring(0, corte) == messageId) repetido = true;
      vigentes.add(linea);
    }

    if (!repetido) vigentes.add('$messageId|$ahora');
    if (vigentes.length > _maximo) {
      vigentes.removeRange(0, vigentes.length - _maximo);
    }

    try {
      await prefs.setStringList(_clave, vigentes);
    } on Object {
      // Si no se pudo escribir, el peor caso es un aviso repetido.
    }
    return repetido;
  }

  /// Id estable para la bandeja del sistema, derivado del `message_id`.
  ///
  /// Antes se usaba el hash del objeto de FCM, distinto en cada entrega: el
  /// mismo mensaje se apilaba como si fueran avisos nuevos.
  static int idNotificacion(String messageId, {required int respaldo}) {
    if (messageId.isEmpty) return respaldo & 0x7fffffff;
    return messageId.hashCode & 0x7fffffff;
  }
}
