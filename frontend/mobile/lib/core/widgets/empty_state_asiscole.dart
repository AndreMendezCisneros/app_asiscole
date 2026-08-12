import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'asiscole_logo.dart';

/// Estado vacío / error reutilizable.
class EmptyStateAsiscole extends StatelessWidget {
  const EmptyStateAsiscole({
    super.key,
    required this.mensaje,
    this.mostrarLogo = true,
    this.onReintentar,
    this.etiquetaReintentar = 'Reintentar',
  });

  final String mensaje;
  final bool mostrarLogo;
  final VoidCallback? onReintentar;
  final String etiquetaReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mostrarLogo) ...[
              const AsiscoleLogo(size: 72),
              const SizedBox(height: 20),
            ],
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textoSecundario,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            if (onReintentar != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onReintentar,
                child: Text(etiquetaReintentar),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
