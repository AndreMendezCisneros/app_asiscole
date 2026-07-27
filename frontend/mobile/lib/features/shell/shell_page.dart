import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Contenedor con barra inferior flotante (RF-K).
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
    return Scaffold(
      backgroundColor: AppTheme.fondo,
      body: navigationShell,
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
                    onTap: () => navigationShell.goBranch(i),
                  ),
                ),
            ],
          ),
        ),
      ),
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
  });

  final _DestinoNav destino;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activo ? AppTheme.moradoPrincipal : AppTheme.textoSecundario;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: activo
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
