import '../network/api_client.dart';
import '../network/auth_interceptor.dart';

/// Respuesta de `GET /sistema/version-app`.
class PoliticaVersion {
  const PoliticaVersion({
    required this.minSoportada,
    required this.ultimaDisponible,
    required this.actualizacionObligatoria,
    required this.actualizacionDisponible,
    this.mensaje,
    this.urlTienda,
  });

  final int minSoportada;
  final int ultimaDisponible;
  final bool actualizacionObligatoria;
  final bool actualizacionDisponible;
  final String? mensaje;
  final String? urlTienda;

  factory PoliticaVersion.fromJson(Map<String, dynamic> json) {
    return PoliticaVersion(
      minSoportada: (json['min_soportada'] as num?)?.toInt() ?? 1,
      ultimaDisponible: (json['ultima_disponible'] as num?)?.toInt() ?? 1,
      actualizacionObligatoria: json['actualizacion_obligatoria'] == true,
      actualizacionDisponible: json['actualizacion_disponible'] == true,
      mensaje: json['mensaje'] as String?,
      urlTienda: json['url_tienda'] as String?,
    );
  }
}

/// Consulta la política de versiones. Falla abierto: si el canal no responde,
/// el arranque de la app no se bloquea.
class VersionAppApi {
  VersionAppApi(this._api);

  final ApiClient _api;

  Future<PoliticaVersion?> consultar({String plataforma = 'android'}) async {
    try {
      final resp = await _api.dio.get<Map<String, dynamic>>(
        '/sistema/version-app',
        queryParameters: {'plataforma': plataforma},
        options: OpcionesAuth.con(EsquemaAuth.ninguno),
      );
      final data = resp.data;
      if (data == null) return null;
      return PoliticaVersion.fromJson(data);
    } on Object {
      return null;
    }
  }
}
