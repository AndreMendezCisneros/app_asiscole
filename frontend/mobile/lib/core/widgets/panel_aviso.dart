import 'package:flutter/material.dart';

import '../theme/asis_colors.dart';

enum TonoAviso { informacion, advertencia, error, exito }

/// Bloque de aviso reutilizable en las pantallas de sesión.
class PanelAviso extends StatelessWidget {
  const PanelAviso({
    super.key,
    required this.texto,
    this.titulo,
    this.tono = TonoAviso.informacion,
    this.icono,
  });

  final String texto;
  final String? titulo;
  final TonoAviso tono;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final (Color fondo, Color acento, IconData iconoPorDefecto) = switch (tono) {
      TonoAviso.informacion => (
          context.asis.moradoClaro.withValues(alpha: 0.15),
          context.asis.morado,
          Icons.info_outline,
        ),
      TonoAviso.advertencia => (
          const Color(0xFFF59E0B).withValues(alpha: 0.18),
          const Color(0xFF92400E),
          Icons.warning_amber_rounded,
        ),
      TonoAviso.error => (
          const Color(0xFFFEE2E2),
          const Color(0xFF991B1B),
          Icons.error_outline,
        ),
      TonoAviso.exito => (
          context.asis.celeste.withValues(alpha: 0.15),
          const Color(0xFF0E7490),
          Icons.check_circle_outline,
        ),
    };

    // Texto siempre oscuro para legibilidad sobre fondos claros/decorativos.
    Color textoCuerpo = context.asis.texto;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.asis.borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono ?? iconoPorDefecto, color: acento, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titulo != null) ...[
                  Text(
                    titulo!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: textoCuerpo,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  texto,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: textoCuerpo,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
