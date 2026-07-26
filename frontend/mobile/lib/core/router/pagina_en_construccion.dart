import 'package:flutter/material.dart';

/// Marcador de una pantalla que aún no existe.
///
/// Fase siguiente: sustituir por las páginas reales de mensajes, asistencias,
/// incidencias y perfil.
class PaginaEnConstruccion extends StatelessWidget {
  const PaginaEnConstruccion({
    super.key,
    required this.titulo,
    required this.detalle,
    this.acciones = const [],
  });

  final String titulo;
  final String detalle;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_outlined,
                  size: 56, color: esquema.primary),
              const SizedBox(height: 20),
              Text(
                detalle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: esquema.onSurfaceVariant, height: 1.4),
              ),
              if (acciones.isNotEmpty) ...[
                const SizedBox(height: 28),
                ...acciones,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
