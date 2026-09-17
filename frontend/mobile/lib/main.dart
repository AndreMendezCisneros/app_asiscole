import 'dart:async';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'app.dart';
import 'core/config/env.dart';
import 'core/crash/crashlytics_canal.dart';
import 'core/di/injector.dart';
import 'core/push/avisos_vistos.dart';
import 'core/push/firebase_init.dart';
import 'core/push/servicio_push.dart';
import 'features/auth/presentation/auth_cubit.dart';

/// Handler en isolate de background (FCM data / notificación).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage mensaje) async {
  // El isolate de background arranca sin plugins registrados.
  DartPluginRegistrant.ensureInitialized();
  await asegurarFirebaseApp();

  final tipo = mensaje.data['tipo']?.toString() ?? '';
  final destino = mensaje.data['destino']?.toString();
  final messageId = mensaje.data['message_id']?.toString() ?? '';

  // Con notification+data, en background/killed Play Services pinta el shade.
  // Este handler cubre data-only residual o mensajes sin bloque notification.
  if (mensaje.notification != null) {
    return;
  }

  // FCM reintenta la entrega cuando el teléfono estaba dormido: sin esta
  // comprobación el mismo aviso reaparece horas después.
  if (await AvisosVistos.yaMostrado(messageId)) {
    return;
  }

  final locales = FlutterLocalNotificationsPlugin();
  const ajustes = InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_stat_asiscole'),
  );
  await locales.initialize(settings: ajustes);
  final android = locales.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android != null) {
    await ServicioPush.asegurarCanalAvisos(android);
  }

  final cuerpo = switch (tipo) {
    'entrada' => 'Hay un nuevo aviso de ingreso',
    'salida' => 'Hay un nuevo aviso de salida',
    'incidencia' => 'Hay una nueva incidencia',
    'aviso' => 'Tienes un nuevo aviso del colegio',
    'nota' => 'Hay una nueva nota',
    _ => 'Tienes un nuevo mensaje',
  };

  await locales.show(
    id: AvisosVistos.idNotificacion(messageId, respaldo: mensaje.hashCode),
    title: Env.nombreApp,
    body: cuerpo,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        ServicioPush.canalId,
        'Avisos del colegio',
        channelDescription: 'Entradas, salidas e incidencias',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('asis_aviso'),
        enableVibration: true,
        icon: '@drawable/ic_stat_asiscole',
        largeIcon: DrawableResourceAndroidBitmap('ic_asiscole_logo'),
        color: Color(0xFF3D5AFE),
        category: AndroidNotificationCategory.message,
      ),
    ),
    payload: destino,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Antes del primer frame solo queda lo que la primera pantalla necesita.
  // Dataset TZ acotado (no `latest_all`) — solo necesitamos America/Lima.
  tz_data.initializeTimeZones();
  // Los formatos con locale explícito (`DateFormat(..., 'es_PE')`) fallan si no
  // están cargados, y se construyen en campos estáticos de varias pantallas.
  await initializeDateFormatting(Env.locale);
  Intl.defaultLocale = Env.locale;

  await configurarInyector();

  // La sesión se restaura en segundo plano: el router muestra `ArranquePage`
  // mientras `Authenticating.restaurando` esté vigente, así que no hay flash de
  // login y el primer frame no espera a la red.
  unawaited(sl<AuthCubit>().iniciar());

  runApp(const AsiscoleApp());

  // Firebase, Crashlytics y push salen del camino crítico: en gama media
  // costaban varios segundos de pantalla en blanco.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_arrancarServiciosDeFondo());
  });
}

Future<void> _arrancarServiciosDeFondo() async {
  // Firebase antes del handler de background para evitar carrera duplicate-app.
  await asegurarFirebaseApp();
  await CrashlyticsCanal.enganchar();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await sl<ServicioPush>().iniciar();
}
