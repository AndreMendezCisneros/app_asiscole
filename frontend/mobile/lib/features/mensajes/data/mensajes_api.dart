import 'package:dio/dio.dart';

import '../domain/mensaje.dart';

class MensajesApi {
  MensajesApi(this._dio);

  final Dio _dio;

  Future<({List<Mensaje> items, Map<String, int> badges, String? nextCursor})>
      listar({
    String? since,
    String? cursor,
    int limit = 100,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/mensajes',
      queryParameters: {
        'since': ?since,
        'cursor': ?cursor,
        'limit': limit,
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
    final next = data['next_cursor'] as String?;
    return (items: items, badges: badges, nextCursor: next);
  }

  Future<void> marcarLeidos(List<String> ids) async {
    if (ids.isEmpty) return;
    await _dio.post<void>('/mensajes/leidos', data: {'ids': ids});
  }
}
