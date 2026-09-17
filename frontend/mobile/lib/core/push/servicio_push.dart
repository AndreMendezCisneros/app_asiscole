import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/env.dart';
import 'avisos_vistos.dart';
import 'firebase_init.dart';

/// Notificaciones push. Payload mínimo del backend: tipo, message_id, destino.
class ServicioPush {
  ServicioPush([FirebaseMessaging? mensajeria]) : _mensajeriaInyectada = mensajeria;

  /// Canal actual. Si Android bloquea uno viejo (IMPORTANCE_NONE), hay que
  /// subir de versión: el mismo ID no recupera importancia. Tampoco se puede
  /// cambiar el sonido de un canal ya creado, y por eso el sonido propio llega
  /// en `v4` en lugar de modificar `v3`.
  static const String canalId = 'asiscole_avisos_v4';

  /// Sonido de marca en `res/raw`. Se declara sin extensión, como exige Android.
  static const String _sonidoCanal = 'asis_aviso';

  /// Canal que el backend nombra en el push (`FCM_ANDROID_CHANNEL_ID`).
  ///
  /// Se sigue creando aunque la app ya no lo use para sus propias
  /// notificaciones: las que pinta Play Services llevan ese `channel_id` y sin
  /// el canal no se mostrarían. Dejará de hacer falta cuando el servidor
  /// apunte a [canalId], y eso solo puede pasar cuando ya nadie use la versión
  /// instalada.
  static const String canalBackendId = 'asiscole_avisos_v3';

  static const List<String> _canalesObsoletos = [
    'asiscole_avisos',
    'asiscole_avisos_v2',
  ];
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
  final StreamController<void> _avisosNota =
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

  /// Se emite cuando llega un push de nota (hay que refrescar la sección).
  Stream<void> get avisosDeNota => _avisosNota.stream;

  /// Nuevo token FCM/APNs (login o rotación).
  Stream<String> get tokensActualizados => _tokensActualizados.stream;

  Future<void> iniciar() async {
    try {
      await asegurarFirebaseApp();
      _mensajeria = _mensajeriaInyectada ?? FirebaseMessaging.instance;
      final permiso = await _mensajeria!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permiso.authorizationStatus == AuthorizationStatus.denied) {
        developer.log('push permiso denegado', name: 'push');
      }
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
        developer.log('push activo', name: 'push');
      } else {
        developer.log('push sin token FCM', name: 'push');
      }
    } on Object catch (e) {
      _activo = false;
      // Solo tipo + mensaje corto; nunca tokens ni payloads.
      developer.log(
        'push inactivo: ${e.runtimeType}: $e',
        name: 'push',
      );
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

  /// Borra el token FCM/APNs del dispositivo al cerrar sesión.
  ///
  /// El backend desactiva el token en `POST /auth/logout`, pero esa petición
  /// puede no llegar (sin red) y el apoderado seguiría recibiendo avisos que no
  /// puede abrir. Borrarlo aquí corta la entrega en el propio teléfono; el
  /// servidor se enterará porque el proveedor empezará a rechazar ese token.
  Future<void> revocarToken() async {
    try {
      await (_mensajeria ?? FirebaseMessaging.instance).deleteToken();
    } on Object {
      // Sin Play Services o sin token previo no hay nada que revocar.
    }
    _activo = false;
  }

  Future<void> _iniciarNotificacionesLocales() async {
    const ajustes = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_asiscole'),
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
    if (android != null) {
      await asegurarCanalAvisos(android, purgarObsoletos: true);
    }
    await android?.requestNotificationsPermission();
  }

  /// Crea los canales vigentes. `purgarObsoletos` solo en arranque.
  ///
  /// Son dos: el que usa la app ([canalId], con sonido de marca) y el que
  /// nombra el backend ([canalBackendId], con el sonido del sistema).
  static Future<void> asegurarCanalAvisos(
    AndroidFlutterLocalNotificationsPlugin android, {
    bool purgarObsoletos = false,
  }) async {
    if (purgarObsoletos) {
      for (final id in _canalesObsoletos) {
        try {
          await android.deleteNotificationChannel(channelId: id);
        } on Object {
          // Canal inexistente: ignorar.
        }
      }
    }
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        canalId,
        'Avisos del colegio',
        description: 'Entradas, salidas e incidencias',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_sonidoCanal),
        enableVibration: true,
        showBadge: true,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        canalBackendId,
        'Avisos del colegio',
        description: 'Entradas, salidas e incidencias',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  void _alRecibir(RemoteMessage mensaje) {
    final destino = _destinoDe(mensaje);
    final tipo = mensaje.data['tipo']?.toString() ?? '';
    final aviso = mensaje.notification;
    final messageId = mensaje.data['message_id']?.toString() ?? '';

    // FCM del canal es solo `data` (sin texto personal). Mostramos aviso genérico.
    final titulo = aviso?.title ?? Env.nombreApp;
    final cuerpo = aviso?.body ?? _textoGenerico(tipo);

    unawaited(_mostrarSiEsNuevo(
      messageId: messageId,
      respaldoId: mensaje.hashCode,
      titulo: titulo,
      cuerpo: cuerpo,
      payload: destino,
    ));

    // La bandeja se refresca aunque el aviso fuera repetido: puede traer datos
    // que la pantalla todavía no tiene.
    _avisarDestino(destino);
  }

  Future<void> _mostrarSiEsNuevo({
    required String messageId,
    required int respaldoId,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    if (await AvisosVistos.yaMostrado(messageId)) return;
    await _mostrarEnBandeja(
      id: AvisosVistos.idNotificacion(messageId, respaldo: respaldoId),
      titulo: titulo,
      cuerpo: cuerpo,
      payload: payload,
    );
  }

  Future<void> _mostrarEnBandeja({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) {
    return _locales.show(
      id: id,
      title: titulo,
      body: cuerpo,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          canalId,
          'Avisos del colegio',
          channelDescription: 'Entradas, salidas e incidencias',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(_sonidoCanal),
          enableVibration: true,
          icon: '@drawable/ic_stat_asiscole',
          largeIcon: DrawableResourceAndroidBitmap('ic_asiscole_logo'),
          color: Color(0xFF3D5AFE),
          category: AndroidNotificationCategory.message,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  void _alAbrir(RemoteMessage mensaje) {
    _avisarDestino(_destinoDe(mensaje));
  }

  void _avisarDestino(String? destino) {
    if (destino == null) return;
    if (destino.startsWith('mensajes/')) {
      _avisosMensaje.add(null);
    }
    if (destino.startsWith('notas/')) {
      _avisosNota.add(null);
    }
    _procesarDestino(destino);
  }

  String _textoGenerico(String tipo) => switch (tipo) {
        'entrada' => 'Hay un nuevo aviso de ingreso',
        'salida' => 'Hay un nuevo aviso de salida',
        'incidencia' => 'Hay una nueva incidencia',
        'aviso' => 'Tienes un nuevo aviso del colegio',
        'nota' => 'Hay una nueva nota',
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
    await _avisosNota.close();
    await _tokensActualizados.close();
  }
}
