import 'package:flutter/material.dart';

/// Cabecera de marca de las pantallas de sesión.
class EncabezadoAsiscole extends StatelessWidget {
  const EncabezadoAsiscole({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.icono = Icons.school_outlined,
  });

  final String titulo;
  final String? subtitulo;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: esquema.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icono, color: esquema.onPrimary, size: 30),
        ),
        const SizedBox(height: 20),
        Text(
          titulo,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitulo!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: esquema.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
      ],
    );
  }
}
