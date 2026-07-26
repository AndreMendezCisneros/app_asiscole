import 'package:dio/dio.dart';

import '../domain/mensaje.dart';

class MensajesApi {
  MensajesApi(this._dio);

  final Dio _dio;

  Future<({List<Mensaje> items, Map<String, int> badges})> listar({
    String? since,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/mensajes',
      queryParameters: {
        'since': ?since,
        'limit': 100,
      },
    );
    final data = resp.data ?? {};
    final items = (data['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(Mensaje.fromJson)
        .toList();
    final badges = Map<String, int>.from(
      (data['no_leidos_por_canal'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      ),
    );
    return (items: items, badges: badges);
  }

  Future<void> marcarLeidos(List<String> ids) async {
    if (ids.isEmpty) return;
    await _dio.post<void>('/mensajes/leidos', data: {'ids': ids});
  }
}
