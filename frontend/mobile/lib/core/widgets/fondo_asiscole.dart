import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Variantes de fondo decorativo por pantalla (mismas manchas de marca,
/// distinta composición).
enum FondoEstilo {
  login,
  mensajes,
  asistencias,
  incidencias,
  notas,
  perfil,
}

/// Manchas suaves morado/celeste detrás del contenido.
class FondoAsiscole extends StatelessWidget {
  const FondoAsiscole({super.key, required this.estilo});

  final FondoEstilo estilo;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: switch (estilo) {
        FondoEstilo.login => const _ComposicionLogin(),
        FondoEstilo.mensajes => const _ComposicionMensajes(),
        FondoEstilo.asistencias => const _ComposicionAsistencias(),
        FondoEstilo.incidencias => const _ComposicionIncidencias(),
        FondoEstilo.notas => const _ComposicionNotas(),
        FondoEstilo.perfil => const _ComposicionPerfil(),
      },
    );
  }
}

class _Bola extends StatelessWidget {
  const _Bola({
    required this.size,
    required this.color,
    this.borderRadius,
    this.angulo = 0,
  });

  final double size;
  final Color color;
  final BorderRadius? borderRadius;
  final double angulo;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius ?? BorderRadius.circular(size),
      ),
    );
    if (angulo == 0) return child;
    return Transform.rotate(angle: angulo, child: child);
  }
}

class _ComposicionLogin extends StatelessWidget {
  const _ComposicionLogin();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: -80,
          right: -60,
          child: _Bola(size: 220, color: Color(0x29A855F7)),
        ),
        Positioned(
          top: 120,
          left: -90,
          child: _Bola(size: 180, color: Color(0x1F22C7F2)),
        ),
        Positioned(
          bottom: 40,
          right: -40,
          child: _Bola(size: 140, color: Color(0x145B21E6)),
        ),
      ],
    );
  }
}

/// Elipses horizontales a la izquierda + acento inferior.
class _ComposicionMensajes extends StatelessWidget {
  const _ComposicionMensajes();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -40,
          left: -100,
          child: Transform.scale(
            scaleX: 1.5,
            child: const _Bola(size: 160, color: Color(0x245B21E6)),
          ),
        ),
        Positioned(
          top: 200,
          right: -70,
          child: Transform.rotate(
            angle: -0.35,
            child: Container(
              width: 200,
              height: 110,
              decoration: BoxDecoration(
                color: AppTheme.celeste.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(80),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 120,
          left: 40,
          child: const _Bola(size: 90, color: Color(0x1FA855F7)),
        ),
      ],
    );
  }
}

/// Cuadrados redondeados tipo “tiles” (calendario).
class _ComposicionAsistencias extends StatelessWidget {
  const _ComposicionAsistencias();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: -50,
          right: -30,
          child: _Bola(
            size: 170,
            color: Color(0x1F22C7F2),
            borderRadius: BorderRadius.all(Radius.circular(48)),
            angulo: 0.4,
          ),
        ),
        Positioned(
          top: 280,
          left: -60,
          child: _Bola(
            size: 130,
            color: Color(0x245B21E6),
            borderRadius: BorderRadius.all(Radius.circular(36)),
            angulo: -0.25,
          ),
        ),
        Positioned(
          bottom: 80,
          right: 20,
          child: _Bola(
            size: 70,
            color: Color(0x1FA855F7),
            borderRadius: BorderRadius.all(Radius.circular(20)),
            angulo: 0.6,
          ),
        ),
      ],
    );
  }
}

/// Diagonales / “rayas” suaves + círculo bajo.
class _ComposicionIncidencias extends StatelessWidget {
  const _ComposicionIncidencias();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 60,
          right: -90,
          child: Transform.rotate(
            angle: math.pi / 5,
            child: Container(
              width: 240,
              height: 70,
              decoration: BoxDecoration(
                color: AppTheme.moradoPrincipal.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(40),
              ),
            ),
          ),
        ),
        Positioned(
          top: 160,
          right: -50,
          child: Transform.rotate(
            angle: math.pi / 5,
            child: Container(
              width: 180,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.moradoClaro.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
        const Positioned(
          bottom: -40,
          left: -50,
          child: _Bola(size: 200, color: Color(0x1A22C7F2)),
        ),
      ],
    );
  }
}

/// Arcos / medias lunas arriba y abajo.
class _ComposicionNotas extends StatelessWidget {
  const _ComposicionNotas();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          left: 40,
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              color: AppTheme.moradoClaro.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(140),
                bottomRight: Radius.circular(140),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 60,
          right: -80,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.celeste.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(120),
              ),
            ),
          ),
        ),
        const Positioned(
          bottom: 200,
          left: -30,
          child: _Bola(size: 60, color: Color(0x1E7C3AED)),
        ),
      ],
    );
  }
}

/// Composición más quieta (respeta el header morado del perfil).
class _ComposicionPerfil extends StatelessWidget {
  const _ComposicionPerfil();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: 260,
          left: -70,
          child: _Bola(size: 150, color: Color(0x145B21E6)),
        ),
        Positioned(
          bottom: 40,
          right: -60,
          child: _Bola(
            size: 180,
            color: Color(0x1F22C7F2),
            borderRadius: BorderRadius.all(Radius.circular(60)),
            angulo: -0.5,
          ),
        ),
        Positioned(
          bottom: 220,
          left: 80,
          child: _Bola(size: 50, color: Color(0x1AA855F7)),
        ),
      ],
    );
  }
}
