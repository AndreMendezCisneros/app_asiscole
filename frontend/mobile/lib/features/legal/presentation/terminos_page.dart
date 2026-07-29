import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/legal/terminos_legales.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fondo_asiscole.dart';

/// Lectura de términos y condiciones (login o perfil).
class TerminosPage extends StatefulWidget {
  const TerminosPage({
    super.key,
    this.aceptadosEn,
  });

  /// Fecha de aceptación (perfil); null en flujo de login.
  final DateTime? aceptadosEn;

  @override
  State<TerminosPage> createState() => _TerminosPageState();
}

class _TerminosPageState extends State<TerminosPage> {
  String? _texto;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final crudo = await rootBundle.loadString(TerminosLegales.assetPath);
      if (mounted) setState(() => _texto = crudo);
    } on Object {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el documento.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.fondo,
      appBar: AppBar(
        title: const Text(TerminosLegales.titulo),
        backgroundColor: AppTheme.blanco,
        foregroundColor: AppTheme.texto,
      ),
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.perfil),
          if (_error != null)
            Center(child: Text(_error!))
          else if (_texto == null)
            const Center(child: CircularProgressIndicator())
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  'Versión ${TerminosLegales.version}',
                  style: const TextStyle(
                    color: AppTheme.textoSecundario,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.aceptadosEn != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Aceptados el ${_fmt(widget.aceptadosEn!)}',
                    style: const TextStyle(
                      color: AppTheme.textoSecundario,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SelectableText(
                  _texto!,
                  style: const TextStyle(
                    color: AppTheme.texto,
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    final local = d.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$dd/$mm/${local.year}';
  }
}
