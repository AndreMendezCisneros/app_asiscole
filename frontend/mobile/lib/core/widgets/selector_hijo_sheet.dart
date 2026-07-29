import 'package:flutter/material.dart';

import '../di/injector.dart';
import '../theme/app_theme.dart';
import '../../features/perfil/data/perfil_repository.dart';

/// Bottom sheet para cambiar el estudiante activo sin salir de la sección.
Future<bool> mostrarSelectorHijo({
  required BuildContext context,
  required int? estudianteActivoId,
}) async {
  final repo = sl<PerfilRepository>();
  List<EstudianteVinculado> hijos;
  try {
    hijos = await repo.estudiantes(forzar: true);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los hijos.')),
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  if (hijos.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solo tienes un estudiante vinculado.')),
    );
    return false;
  }

  final elegido = await showModalBottomSheet<EstudianteVinculado>(
    context: context,
    backgroundColor: AppTheme.fondo,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borde,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '¿A qué hijo quieres ver?',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppTheme.texto,
                ),
              ),
              const SizedBox(height: 8),
              ...hijos.map((h) {
                final activo = h.id == estudianteActivoId || h.activo;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    activo ? Icons.check_circle : Icons.circle_outlined,
                    color: activo
                        ? AppTheme.celeste
                        : AppTheme.moradoSecundario,
                  ),
                  title: Text(
                    h.nombre,
                    style: TextStyle(
                      fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
                      color: AppTheme.texto,
                    ),
                  ),
                  subtitle: Text(
                    '${h.grado} ${h.seccion} · ${h.colegio}'.trim(),
                    style: const TextStyle(
                      color: AppTheme.textoSecundario,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, h),
                );
              }),
            ],
          ),
        ),
      );
    },
  );

  if (elegido == null || !context.mounted) return false;
  if (elegido.id == estudianteActivoId) return false;

  try {
    await repo.seleccionarEstudiante(elegido.id);
    return true;
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar de hijo.')),
      );
    }
    return false;
  }
}
