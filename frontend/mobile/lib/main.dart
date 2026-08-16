import 'dart:async';

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
import 'core/push/firebase_init.dart';
import 'core/push/servicio_push.dart';
import 'features/auth/presentation/auth_cubit.dart';

/// Handler en isolate de background (FCM data / notificación).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage mensaje) async {
  await asegurarFirebaseApp();

  final tipo = mensaje.data['tipo']?.toString() ?? '';
  final destino = mensaje.data['destino']?.toString();

  // Con notification+data, en background/killed Play Services pinta el shade.
  // Este handler cubre data-only residual o mensajes sin bloque notification.
  if (mensaje.notification != null) {
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
    id: mensaje.hashCode,
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

  // Dataset TZ acotado (no `latest_all`) — solo necesitamos America/Lima.
  tz_data.initializeTimeZones();
  await initializeDateFormatting(Env.locale);
  Intl.defaultLocale = Env.locale;

  // Firebase antes del handler de background para evitar carrera duplicate-app.
  await asegurarFirebaseApp();
  await CrashlyticsCanal.enganchar();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await configurarInyector();

  // Restaurar sesión antes del primer frame para evitar flash de login.
  await sl<AuthCubit>().iniciar();

  runApp(const AsiscoleApp());

  // Push fuera del camino critico de arranque (Firebase ya está listo).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(sl<ServicioPush>().iniciar());
  });
}
