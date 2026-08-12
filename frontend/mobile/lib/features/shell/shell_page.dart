import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../auth/presentation/auth_cubit.dart';
import '../auth/presentation/auth_state.dart';

/// Contenedor con barra inferior flotante (RF-K).
///
/// Offline (`OfflineMessagesOnly`): solo la pestaña Mensajes es usable;
/// el resto queda deshabilitado (regla de producto: solo caché de mensajes).
class ShellPage extends StatelessWidget {
  const ShellPage({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinos = <_DestinoNav>[
    _DestinoNav(
      icono: Icons.chat_bubble_outline,
      iconoActivo: Icons.chat_bubble,
      etiqueta: 'Mensajes',
    ),
    _DestinoNav(
      icono: Icons.calendar_today_outlined,
      iconoActivo: Icons.calendar_today,
      etiqueta: 'Asistencias',
    ),
    _DestinoNav(
      icono: Icons.report_outlined,
      iconoActivo: Icons.report,
      etiqueta: 'Incidencias',
    ),
    _DestinoNav(
      icono: Icons.school_outlined,
      iconoActivo: Icons.school,
      etiqueta: 'Notas',
    ),
    _DestinoNav(
      icono: Icons.person_outline,
      iconoActivo: Icons.person,
      etiqueta: 'Perfil',
    ),
  ];

  static const _sombraNav = [
    BoxShadow(
      color: Color(0x140F172A),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
  static final _decoNav = BoxDecoration(
    color: AppTheme.blanco,
    borderRadius: BorderRadius.circular(28),
    border: const Border.fromBorderSide(BorderSide(color: AppTheme.borde)),
    boxShadow: _sombraNav,
  );

  @override
  Widget build(BuildContext context) {
    final indice = navigationShell.currentIndex;
    return BlocBuilder<AuthCubit, AuthState>(
      buildWhen: (prev, next) =>
          prev.runtimeType != next.runtimeType ||
          (prev is OfflineMessagesOnly) != (next is OfflineMessagesOnly),
      builder: (context, auth) {
        final soloMensajes = auth is OfflineMessagesOnly;
        if (soloMensajes && indice != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigationShell.goBranch(0);
          });
        }
        return Scaffold(
          backgroundColor: AppTheme.fondo,
          body: Column(
            children: [
              if (soloMensajes)
                Material(
                  color: const Color(0xFFFFF3CD),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.wifi_off,
                            size: 18,
                            color: Color(0xFF856404),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sin conexión — solo mensajes guardados',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                color: const Color(0xFF856404),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(child: navigationShell),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: _decoNav,
              child: Row(
                children: [
                  for (var i = 0; i < _destinos.length; i++)
                    Expanded(
                      child: _ItemNav(
                        destino: _destinos[i],
                        activo: i == indice,
                        habilitado: !soloMensajes || i == 0,
                        onTap: () {
                          if (soloMensajes && i != 0) return;
                          navigationShell.goBranch(i);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DestinoNav {
  const _DestinoNav({
    required this.icono,
    required this.iconoActivo,
    required this.etiqueta,
  });

  final IconData icono;
  final IconData iconoActivo;
  final String etiqueta;
}

class _ItemNav extends StatelessWidget {
  const _ItemNav({
    required this.destino,
    required this.activo,
    required this.onTap,
    this.habilitado = true,
  });

  final _DestinoNav destino;
  final bool activo;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !habilitado
        ? AppTheme.textoSecundario.withValues(alpha: 0.35)
        : activo
            ? AppTheme.moradoPrincipal
            : AppTheme.textoSecundario;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: habilitado ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: activo && habilitado
                ? const Color(0x38A855F7)
                : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                activo ? destino.iconoActivo : destino.icono,
                size: 22,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                destino.etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
