import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

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

  // Fechas y horas siempre en español de Perú y zona del colegio.
  tz_data.initializeTimeZones();
  await initializeDateFormatting(Env.locale);
  Intl.defaultLocale = Env.locale;

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await configurarInyector();
  await sl<ServicioPush>().iniciar();

  // Se restaura la sesión antes de pintar para no mostrar el login en vano.
  await sl<AuthCubit>().iniciar();

  runApp(const AsiscoleApp());
}
