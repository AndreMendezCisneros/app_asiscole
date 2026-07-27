import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Indicador compacto del estado de asistencia de un día.
class DayStatusBadge extends StatelessWidget {
  const DayStatusBadge({super.key, required this.estado, this.compacto = false});

  final String estado;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (estado) {
      'a_tiempo' => ('A tiempo', AppTheme.celeste),
      'tarde' => ('Tarde', AppTheme.ambar),
      'falta' => ('Falta', AppTheme.moradoPrincipal),
      _ => ('Sin registro', AppTheme.textoSecundario),
    };

    if (compacto) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
