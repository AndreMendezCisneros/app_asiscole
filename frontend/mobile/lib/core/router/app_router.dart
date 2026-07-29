import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/asistencias/presentation/asistencias_page.dart';
import '../../features/auth/presentation/aprobar_transferencia_page.dart';
import '../../features/auth/presentation/auth_cubit.dart';
import '../../features/auth/presentation/auth_state.dart';
import '../../features/auth/presentation/cuenta_suspendida_page.dart';
import '../../features/auth/presentation/esperando_aprobacion_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/sesion_denegada_page.dart';
import '../../features/incidencias/presentation/incidencias_page.dart';
import '../../features/legal/presentation/terminos_page.dart';
import '../../features/mensajes/presentation/mensajes_page.dart';
import '../../features/notas/presentation/notas_page.dart';
import '../../features/perfil/presentation/perfil_page.dart';
import '../../features/shell/shell_page.dart';

class Rutas {
  const Rutas._();

  static const String login = '/login';
  static const String sesionDenegada = '/sesion-denegada';
  static const String esperandoAprobacion = '/esperando-aprobacion';
  static const String cuentaSuspendida = '/cuenta-suspendida';
  static const String aprobarTransferencia = '/transferencia';
  static const String inicio = '/inicio';
  static const String mensajes = '/inicio/mensajes';
  static const String asistencias = '/inicio/asistencias';
  static const String incidencias = '/inicio/incidencias';
  static const String notas = '/inicio/notas';
  static const String perfil = '/inicio/perfil';
  static const String terminos = '/terminos';
}

GoRouter crearRouter(AuthCubit auth) {
  return GoRouter(
    initialLocation: Rutas.login,
    debugLogDiagnostics: false,
    refreshListenable: _EscuchaDeEstado(auth.stream),
    redirect: (context, estado) => _destino(auth.state, estado.matchedLocation),
    routes: [
      GoRoute(path: Rutas.login, builder: (_, _) => const LoginPage()),
      GoRoute(
        path: Rutas.terminos,
        builder: (_, estado) {
          final extra = estado.extra;
          DateTime? aceptados;
          if (extra is DateTime) aceptados = extra;
          return TerminosPage(aceptadosEn: aceptados);
        },
      ),
      GoRoute(
        path: Rutas.sesionDenegada,
        builder: (_, _) => const SesionDenegadaPage(),
      ),
      GoRoute(
        path: Rutas.esperandoAprobacion,
        builder: (_, _) => const EsperandoAprobacionPage(),
      ),
      GoRoute(
        path: Rutas.cuentaSuspendida,
        builder: (_, _) => const CuentaSuspendidaPage(),
      ),
      GoRoute(
        path: '${Rutas.aprobarTransferencia}/:id',
        builder: (_, estado) => AprobarTransferenciaPage(
          idSolicitud: estado.pathParameters['id'] ?? '',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellPage(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.mensajes,
                builder: (_, _) => const MensajesPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.asistencias,
                builder: (_, _) => const AsistenciasPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.incidencias,
                builder: (_, _) => const IncidenciasPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.notas,
                builder: (_, _) => const NotasPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Rutas.perfil,
                builder: (_, _) => const PerfilPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

String? _destino(AuthState auth, String actual) {
  if (auth is Authenticating) return null;

  // Términos legibles sin sesión (desde login) o con sesión (desde perfil).
  if (actual == Rutas.terminos) return null;

  final tieneSesion = auth is OnlineSync || auth is OfflineMessagesOnly;

  if (actual.startsWith('${Rutas.aprobarTransferencia}/')) {
    return tieneSesion ? null : Rutas.login;
  }

  final destino = switch (auth) {
    Unauthenticated() => Rutas.login,
    Authenticating() => Rutas.login,
    OnlineSync() || OfflineMessagesOnly() => Rutas.mensajes,
    LoginDenied() => Rutas.sesionDenegada,
    AwaitingTransferApproval() => Rutas.esperandoAprobacion,
    Suspended() => Rutas.cuentaSuspendida,
  };

  if (tieneSesion && actual.startsWith(Rutas.inicio)) return null;
  return actual == destino ? null : destino;
}

class _EscuchaDeEstado extends ChangeNotifier {
  _EscuchaDeEstado(Stream<AuthState> stream) {
    _suscripcion = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _suscripcion;

  @override
  void dispose() {
    _suscripcion.cancel();
    super.dispose();
  }
}
