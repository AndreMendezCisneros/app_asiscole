import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones push. Payload mínimo del backend: tipo, message_id, destino.
class ServicioPush {
  ServicioPush([FirebaseMessaging? mensajeria]) : _mensajeriaInyectada = mensajeria;

  static const String canalId = 'asiscole_avisos';
  static const String tipoSolicitudTransferencia = 'session_transfer_request';

  final FirebaseMessaging? _mensajeriaInyectada;
  FirebaseMessaging? _mensajeria;
  bool _activo = false;

  final StreamController<String> _transferencias =
      StreamController<String>.broadcast();
  final StreamController<String> _destinos =
      StreamController<String>.broadcast();

  final FlutterLocalNotificationsPlugin _locales =
      FlutterLocalNotificationsPlugin();

  bool get activo => _activo;

  /// Ids de solicitudes de traspaso (dispositivo con sesión activa).
  Stream<String> get solicitudesDeTransferencia => _transferencias.stream;

  /// Deep-links técnicos (`mensajes/<uuid>`, `incidencias/<id>`, …).
  Stream<String> get deepLinks => _destinos.stream;

  Future<void> iniciar() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _mensajeria = _mensajeriaInyectada ?? FirebaseMessaging.instance;
      await _mensajeria!.requestPermission();
      await _iniciarNotificacionesLocales();

      FirebaseMessaging.onMessage.listen(_alRecibir);
      FirebaseMessaging.onMessageOpenedApp.listen(_alAbrir);
      final inicial = await _mensajeria!.getInitialMessage();
      if (inicial != null) _alAbrir(inicial);

      _activo = true;
    } on Object catch (e) {
      _activo = false;
      developer.log('push inactivo: ${e.runtimeType}', name: 'push');
    }
  }

  Future<String?> token() async {
    if (!_activo) return null;
    try {
      return await _mensajeria?.getToken();
    } on Object {
      return null;
    }
  }

  Future<void> _iniciarNotificacionesLocales() async {
    const ajustes = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _locales.initialize(
      settings: ajustes,
      onDidReceiveNotificationResponse: (respuesta) {
        final carga = respuesta.payload;
        if (carga != null && carga.isNotEmpty) _procesarDestino(carga);
      },
    );
  }

  void _alRecibir(RemoteMessage mensaje) {
    final destino = _destinoDe(mensaje);
    final aviso = mensaje.notification;
    if (aviso == null) return;

    _locales.show(
      id: mensaje.hashCode,
      title: aviso.title,
      body: aviso.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          canalId,
          'Avisos del colegio',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: destino,
    );
  }

  void _alAbrir(RemoteMessage mensaje) {
    final destino = _destinoDe(mensaje);
    if (destino != null) _procesarDestino(destino);
  }

  String? _destinoDe(RemoteMessage mensaje) {
    final datos = mensaje.data;
    final destino = datos['destino'];
    if (destino is String && destino.isNotEmpty) return destino;
    // Compatibilidad con payloads antiguos de transferencia.
    if (datos['tipo'] == tipoSolicitudTransferencia) {
      final id = datos['transfer_id'];
      if (id is String && id.isNotEmpty) return 'transferencia/$id';
    }
    return null;
  }

  void _procesarDestino(String destino) {
    if (destino.startsWith('transferencia/')) {
      final id = destino.substring('transferencia/'.length);
      if (id.isNotEmpty) _transferencias.add(id);
      return;
    }
    _destinos.add(destino);
  }

  Future<void> cerrar() async {
    await _transferencias.close();
    await _destinos.close();
  }
}
