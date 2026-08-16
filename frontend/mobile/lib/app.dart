import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/env.dart';
import 'core/crash/crashlytics_canal.dart';
import 'core/di/injector.dart';
import 'core/device/info_dispositivo.dart';
import 'core/push/servicio_push.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/version/actualizador_app.dart';
import 'core/version/version_app_api.dart';
import 'features/auth/data/session_storage.dart';
import 'features/auth/presentation/auth_cubit.dart';
import 'features/auth/presentation/auth_state.dart';
import 'features/perfil/data/perfil_repository.dart';
import 'features/sistema/actualizacion_obligatoria_page.dart';

/// Raíz de la aplicación del apoderado.
class AsiscoleApp extends StatefulWidget {
  const AsiscoleApp({super.key});

  @override
  State<AsiscoleApp> createState() => _AsiscoleAppState();
}

class _AsiscoleAppState extends State<AsiscoleApp> {
  final GlobalKey<NavigatorState> _rootNav = GlobalKey<NavigatorState>();
  late final AuthCubit _auth = sl<AuthCubit>();
  late final GoRouter _router = crearRouter(_auth, navigatorKey: _rootNav);
  StreamSubscription<String>? _pushTransferencias;
  StreamSubscription<String>? _pushDeepLinks;
  StreamSubscription<void>? _pushAvisos;
  StreamSubscription<String>? _tokenRefresh;

  PoliticaVersion? _bloqueo;
  static const _claveAvisoUpdate = 'aviso_update_mostrado_en';
  static const _margenAvisoUpdate = Duration(hours: 48);

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
    unawaited(_comprobarVersion());
  }

  /// Fail-open: si el endpoint no responde, la app arranca igual.
  Future<void> _comprobarVersion() async {
    final politica = await sl<VersionAppApi>().consultar();
    if (!mounted || politica == null) return;
    if (politica.actualizacionObligatoria) {
      setState(() => _bloqueo = politica);
      return;
    }
    if (politica.actualizacionDisponible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_avisarUpdateOpcional(politica));
      });
    }
  }

  Future<void> _avisarUpdateOpcional(PoliticaVersion politica) async {
    if (!mounted || _bloqueo != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final previo = prefs.getInt(_claveAvisoUpdate);
      final ahora = DateTime.now().millisecondsSinceEpoch;
      if (previo != null &&
          ahora - previo < _margenAvisoUpdate.inMilliseconds) {
        return;
      }
      await prefs.setInt(_claveAvisoUpdate, ahora);
    } on Object {
      // Sin preferencias, se muestra una vez por arranque.
    }
    if (!mounted) return;
    final ctx = _rootNav.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final actualizar = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hay una versión nueva'),
        content: Text(
          (politica.mensaje ?? '').trim().isEmpty
              ? 'Puedes actualizar ${Env.nombreApp} cuando quieras. '
                  'Esta versión sigue funcionando.'
              : politica.mensaje!,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (actualizar == true) {
      final resultado = await ActualizadorApp.intentar(
        politica: politica,
        inmediata: false,
      );
      if (!mounted) return;
      if (resultado == ResultadoActualizacion.pedirAlColegio) {
        final snackCtx = _rootNav.currentContext;
        if (snackCtx != null && snackCtx.mounted) {
          ScaffoldMessenger.of(snackCtx).showSnackBar(
            const SnackBar(
              content: Text('Pide la versión nueva al colegio.'),
            ),
          );
        }
      }
    }
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

  Future<void> _anotarTenantEnCrashes() async {
    try {
      final hijos = await sl<PerfilRepository>().estudiantes();
      final tenant = hijos
          .map((h) => h.colegio.trim())
          .firstWhere((c) => c.isNotEmpty, orElse: () => '');
      await CrashlyticsCanal.registrarTenant(tenant);
    } on Object {
      // Observabilidad oportunista.
    }
  }

  void _abrirDeepLink(String destino) {
    if (destino.startsWith('mensajes/')) {
      _router.go(Rutas.mensajes);
      return;
    }
    if (destino.startsWith('incidencias/')) {
      _router.go(Rutas.incidencias);
      return;
    }
    if (destino.startsWith('notas/')) {
      _router.go(Rutas.notas);
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
    final bloqueo = _bloqueo;
    if (bloqueo != null) {
      return MaterialApp(
        title: Env.nombreApp,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.claro,
        themeMode: ThemeMode.light,
        locale: const Locale('es', 'PE'),
        supportedLocales: const [Locale('es', 'PE'), Locale('es')],
        home: ActualizacionObligatoriaPage(politica: bloqueo),
      );
    }

    return BlocProvider<AuthCubit>.value(
      value: _auth,
      child: BlocListener<AuthCubit, AuthState>(
        listenWhen: (prev, next) =>
            (next is OnlineSync && prev is! OnlineSync) ||
            (next is OfflineMessagesOnly && prev is! OfflineMessagesOnly),
        listener: (context, estado) {
          if (estado is OnlineSync || estado is OfflineMessagesOnly) {
            _router.go(Rutas.mensajes);
          }
          if (estado is OnlineSync) {
            unawaited(_registrarPushToken());
            unawaited(_anotarTenantEnCrashes());
          }
        },
        child: MaterialApp.router(
          title: Env.nombreApp,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.claro,
          themeMode: ThemeMode.light,
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
