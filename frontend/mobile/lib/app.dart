import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/di/injector.dart';
import 'core/push/servicio_push.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_cubit.dart';

/// Raíz de la aplicación del apoderado.
class AsiscoleApp extends StatefulWidget {
  const AsiscoleApp({super.key});

  @override
  State<AsiscoleApp> createState() => _AsiscoleAppState();
}

class _AsiscoleAppState extends State<AsiscoleApp> {
  late final AuthCubit _auth = sl<AuthCubit>();
  late final GoRouter _router = crearRouter(_auth);
  StreamSubscription<String>? _pushTransferencias;
  StreamSubscription<String>? _pushDeepLinks;

  @override
  void initState() {
    super.initState();
    final push = sl<ServicioPush>();
    _pushTransferencias = push.solicitudesDeTransferencia.listen(
      (id) => _router.push('${Rutas.aprobarTransferencia}/$id'),
    );
    _pushDeepLinks = push.deepLinks.listen(_abrirDeepLink);
  }

  void _abrirDeepLink(String destino) {
    if (destino.startsWith('mensajes/')) {
      _router.go(Rutas.mensajes);
      return;
    }
    if (destino.startsWith('incidencias/')) {
      _router.go(Rutas.incidencias);
    }
  }

  @override
  void dispose() {
    _pushTransferencias?.cancel();
    _pushDeepLinks?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>.value(
      value: _auth,
      child: MaterialApp.router(
        title: 'Asiscole',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.claro,
        darkTheme: AppTheme.oscuro,
        routerConfig: _router,
        locale: const Locale('es', 'PE'),
        supportedLocales: const [Locale('es', 'PE'), Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
