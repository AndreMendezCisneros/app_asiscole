import 'package:flutter/material.dart';

import '../../core/theme/asis_colors.dart';
import '../../core/widgets/asiscole_logo.dart';

/// Pantalla del primer frame, mientras se restaura la sesión guardada.
///
/// Existe para que la app pueda dibujar de inmediato: antes se esperaba a
/// restaurar la sesión antes de `runApp` para no mostrar el login un instante,
/// y eso retrasaba el arranque varios segundos.
class ArranquePage extends StatelessWidget {
  const ArranquePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.asis.fondo,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AsiscoleLogo(size: 96),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: context.asis.morado.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
