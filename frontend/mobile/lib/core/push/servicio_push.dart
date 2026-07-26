import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';

/// Notificaciones push. Payload mínimo del backend: tipo, message_id, destino.
class ServicioPush {
  ServicioPush([FirebaseMessaging? mensajeria]) : _mensajeriaInyectada = mensajeria;

  static const String canalId = 'asiscole_avisos';
  static const String tipoSolicitudTransferencia = 'session_transfer_request';

  final FirebaseMessaging? _mensajeriaInyectada;
  FirebaseMessaging? _mensajeria;
  bool _activo = false;
  StreamSubscription<String>? _tokenRefresh;

  final StreamController<String> _transferencias =
      StreamController<String>.broadcast();
  final StreamController<String> _destinos =
      StreamController<String>.broadcast();
  final StreamController<void> _avisosMensaje =
      StreamController<void>.broadcast();
  final StreamController<String> _tokensActualizados =
      StreamController<String>.broadcast();

  final FlutterLocalNotificationsPlugin _locales =
      FlutterLocalNotificationsPlugin();

  bool get activo => _activo;

  /// Ids de solicitudes de traspaso (dispositivo con sesión activa).
  Stream<String> get solicitudesDeTransferencia => _transferencias.stream;

  /// Deep-links técnicos (`mensajes/<uuid>`, `incidencias/<id>`, …).
  Stream<String> get deepLinks => _destinos.stream;

  /// Se emite cuando llega un push de mensaje (hay que refrescar la bandeja).
  Stream<void> get avisosDeMensaje => _avisosMensaje.stream;

  /// Nuevo token FCM/APNs (login o rotación).
  Stream<String> get tokensActualizados => _tokensActualizados.stream;

  Future<void> iniciar() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _mensajeria = _mensajeriaInyectada ?? FirebaseMessaging.instance;
      await _mensajeria!.requestPermission();
      await _iniciarNotificacionesLocales();

      FirebaseMessaging.onMessage.listen(_alRecibir);
      FirebaseMessaging.onMessageOpenedApp.listen(_alAbrir);
      final inicial = await _mensajeria!.getInitialMessage();
      if (inicial != null) _alAbrir(inicial);

      _tokenRefresh?.cancel();
      _tokenRefresh = _mensajeria!.onTokenRefresh.listen((t) {
        if (t.isNotEmpty) _tokensActualizados.add(t);
      });

      _activo = true;
      final actual = await token();
      if (actual != null && actual.isNotEmpty) {
        _tokensActualizados.add(actual);
      }
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

    final android = _locales.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        canalId,
        'Avisos del colegio',
        description: 'Entradas, salidas e incidencias',
        importance: Importance.high,
      ),
    );
    await android?.requestNotificationsPermission();
  }

  void _alRecibir(RemoteMessage mensaje) {
    final destino = _destinoDe(mensaje);
    final tipo = mensaje.data['tipo']?.toString() ?? '';
    final aviso = mensaje.notification;

    // FCM del canal es solo `data` (sin texto personal). Mostramos aviso genérico.
    final titulo = aviso?.title ?? 'Asiscole Messenger';
    final cuerpo = aviso?.body ?? _textoGenerico(tipo);

    _locales.show(
      id: mensaje.hashCode,
      title: titulo,
      body: cuerpo,
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

    if (destino != null && destino.startsWith('mensajes/')) {
      _avisosMensaje.add(null);
    }
    if (destino != null) _procesarDestino(destino);
  }

  void _alAbrir(RemoteMessage mensaje) {
    final destino = _destinoDe(mensaje);
    if (destino != null && destino.startsWith('mensajes/')) {
      _avisosMensaje.add(null);
    }
    if (destino != null) _procesarDestino(destino);
  }

  String _textoGenerico(String tipo) => switch (tipo) {
        'entrada' => 'Hay un nuevo aviso de ingreso',
        'salida' => 'Hay un nuevo aviso de salida',
        'incidencia' => 'Hay una nueva incidencia',
        'aviso' => 'Tienes un nuevo aviso del colegio',
        tipoSolicitudTransferencia => 'Solicitud de acceso en otro dispositivo',
        _ => 'Tienes un nuevo mensaje',
      };

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
    await _tokenRefresh?.cancel();
    await _transferencias.close();
    await _destinos.close();
    await _avisosMensaje.close();
    await _tokensActualizados.close();
  }
}
