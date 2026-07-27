import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    final (Color fondo, Color contenido, IconData iconoPorDefecto) =
        switch (tono) {
      TonoAviso.informacion => (
          AppTheme.moradoClaro.withValues(alpha: 0.15),
          AppTheme.moradoPrincipal,
          Icons.info_outline,
        ),
      TonoAviso.advertencia => (
          const Color(0xFFF59E0B).withValues(alpha: 0.15),
          const Color(0xFFB45309),
          Icons.warning_amber_rounded,
        ),
      TonoAviso.error => (
          Theme.of(context).colorScheme.errorContainer,
          Theme.of(context).colorScheme.onErrorContainer,
          Icons.error_outline,
        ),
      TonoAviso.exito => (
          AppTheme.celeste.withValues(alpha: 0.15),
          AppTheme.celeste,
          Icons.check_circle_outline,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono ?? iconoPorDefecto, color: contenido, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titulo != null) ...[
                  Text(
                    titulo!,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: contenido, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  texto,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.texto,
                        height: 1.35,
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
