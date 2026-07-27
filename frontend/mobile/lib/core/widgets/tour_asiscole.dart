import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme/app_theme.dart';

/// Tour corto por sección (manual interactivo in-app).
class TourAsiscole {
  TourAsiscole._();

  static const _storage = FlutterSecureStorage();

  static String _clave(String seccion) => 'tour_visto_$seccion';

  static Future<bool> yaVisto(String seccion) async {
    final v = await _storage.read(key: _clave(seccion));
    return v == '1';
  }

  static Future<void> marcarVisto(String seccion) async {
    await _storage.write(key: _clave(seccion), value: '1');
  }

  static Future<void> resetearTodo() async {
    for (final s in const [
      'mensajes',
      'asistencias',
      'incidencias',
      'notas',
      'perfil',
    ]) {
      await _storage.delete(key: _clave(s));
    }
  }

  static Future<void> mostrarSiCorresponde(
    BuildContext context, {
    required String seccion,
    required String titulo,
    required String cuerpo,
    bool forzar = false,
  }) async {
    if (!forzar && await yaVisto(seccion)) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.blanco,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          titulo,
          style: const TextStyle(
            color: AppTheme.texto,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          cuerpo,
          style: const TextStyle(
            color: AppTheme.texto,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await marcarVisto(seccion);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    await marcarVisto(seccion);
  }
}

/// Textos de guía por sección.
class GuiasTour {
  const GuiasTour._();

  static const mensajes = (
    titulo: 'Mensajes',
    cuerpo:
        'Aquí llegan avisos de entrada, salida, incidencias y comunicados. '
        'Puedes filtrar no leídos y, si tienes hijos en distintos colegios, '
        'filtrar por colegio. Toca un mensaje para ver el detalle (solo lectura).',
  );

  static const asistencias = (
    titulo: 'Asistencias',
    cuerpo:
        'El calendario muestra el mes del hijo activo. Los colores indican '
        'a tiempo, tarde o falta. Toca un día para ver entrada, salida y estado.',
  );

  static const incidencias = (
    titulo: 'Incidencias',
    cuerpo:
        'Revisa las incidencias del hijo activo. Confirma que las recibiste '
        'para que el colegio sepa que ya te enteraste. Las citaciones estarán '
        'disponibles más adelante.',
  );

  static const notas = (
    titulo: 'Notas',
    cuerpo:
        'El módulo de notas se activará desde el colegio sin pedirte una '
        'nueva versión de la app. Mientras tanto verás “Próximamente”.',
  );

  static const perfil = (
    titulo: 'Perfil',
    cuerpo:
        'Aquí eliges el hijo activo (afecta asistencias e incidencias), '
        'cierras sesión o eliminas tu cuenta. También puedes volver a ver '
        'esta guía.',
  );
}
