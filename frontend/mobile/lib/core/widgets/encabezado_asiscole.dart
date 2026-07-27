import 'package:flutter/material.dart';

import 'asiscole_logo.dart';
import '../theme/app_theme.dart';

/// Cabecera de marca de las pantallas de sesión.
class EncabezadoAsiscole extends StatelessWidget {
  const EncabezadoAsiscole({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.icono = Icons.school_outlined,
    this.usarLogo = true,
  });

  final String titulo;
  final String? subtitulo;
  final IconData icono;
  final bool usarLogo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (usarLogo)
          const AsiscoleLogo(size: 64)
        else
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.moradoPrincipal,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icono, color: Colors.white, size: 30),
          ),
        const SizedBox(height: 20),
        Text(
          titulo,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTheme.texto,
              ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitulo!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textoSecundario,
                  height: 1.4,
                ),
          ),
        ],
      ],
    );
  }
}
