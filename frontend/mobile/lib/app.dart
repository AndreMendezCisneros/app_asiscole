import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/di/injector.dart';
import 'core/device/info_dispositivo.dart';
import 'core/push/servicio_push.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/session_storage.dart';
import 'features/auth/presentation/auth_cubit.dart';
import 'features/auth/presentation/auth_state.dart';
import 'features/perfil/data/perfil_repository.dart';

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
  StreamSubscription<void>? _pushAvisos;
  StreamSubscription<String>? _tokenRefresh;

  @override
  void initState() {
    super.initState();
    final push = sl<ServicioPush>();
    _pushTransferencias = push.solicitudesDeTransferencia.listen(
      (id) => _router.push('${Rutas.aprobarTransferencia}/$id'),
    );
    _pushDeepLinks = push.deepLinks.listen(_abrirDeepLink);
    _pushAvisos = push.avisosDeMensaje.listen((_) {
      if (_auth.state is OnlineSync) {
        _router.go(Rutas.mensajes);
      }
    });
    _tokenRefresh = push.tokensActualizados.listen((_) => _registrarPushToken());
    // El registro real ocurre cuando ServicioPush emite el token (post-frame).
  }

  Future<void> _registrarPushToken() async {
    if (!await sl<SessionStorage>().haySesion) return;
    try {
      final token = await sl<ServicioPush>().token();
      if (token == null || token.isEmpty) return;
      final datos = await sl<InfoDispositivo>().obtener(
        await sl<SessionStorage>().deviceId(),
      );
      await sl<PerfilRepository>().registrarPushToken(
        token: token,
        plataforma: datos.plataforma,
      );
    } on Object {
      // Push es oportunista: el login y la bandeja siguen sin él.
    }
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
    _pushAvisos?.cancel();
    _tokenRefresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>.value(
      value: _auth,
      child: BlocListener<AuthCubit, AuthState>(
        listenWhen: (prev, next) =>
            (next is OnlineSync && prev is! OnlineSync) ||
            (next is OfflineMessagesOnly && prev is! OfflineMessagesOnly),
        listener: (context, estado) {
          if (estado is OnlineSync || estado is OfflineMessagesOnly) {
            // Fuerza entrada al shell aunque el refresh de GoRouter falle.
            _router.go(Rutas.mensajes);
          }
          if (estado is OnlineSync) {
            unawaited(_registrarPushToken());
          }
        },
        child: MaterialApp.router(
          title: 'Asiscole Messenger',
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
      ),
    );
  }
}
