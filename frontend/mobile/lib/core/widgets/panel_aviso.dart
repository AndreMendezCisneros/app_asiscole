import 'package:flutter/material.dart';

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
    final esquema = Theme.of(context).colorScheme;
    final (Color fondo, Color contenido, IconData iconoPorDefecto) =
        switch (tono) {
      TonoAviso.informacion => (
          esquema.secondaryContainer,
          esquema.onSecondaryContainer,
          Icons.info_outline,
        ),
      TonoAviso.advertencia => (
          esquema.tertiaryContainer,
          esquema.onTertiaryContainer,
          Icons.warning_amber_rounded,
        ),
      TonoAviso.error => (
          esquema.errorContainer,
          esquema.onErrorContainer,
          Icons.error_outline,
        ),
      TonoAviso.exito => (
          esquema.primaryContainer,
          esquema.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
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
                        ?.copyWith(color: contenido),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  texto,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: contenido, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
