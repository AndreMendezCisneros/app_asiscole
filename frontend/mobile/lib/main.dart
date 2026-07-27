import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'app.dart';
import 'core/config/env.dart';
import 'core/di/injector.dart';
import 'core/push/servicio_push.dart';
import 'features/auth/presentation/auth_cubit.dart';
import 'firebase_options.dart';

/// Handler en isolate de background (FCM data / notificación).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage mensaje) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dataset TZ acotado (no `latest_all`) — solo necesitamos America/Lima.
  tz_data.initializeTimeZones();
  await initializeDateFormatting(Env.locale);
  Intl.defaultLocale = Env.locale;

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await configurarInyector();

  // Restaurar sesión antes del primer frame para evitar flash de login.
  await sl<AuthCubit>().iniciar();

  runApp(const AsiscoleApp());

  // Push/Firebase fuera del camino crítico de arranque.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(sl<ServicioPush>().iniciar());
  });
}
