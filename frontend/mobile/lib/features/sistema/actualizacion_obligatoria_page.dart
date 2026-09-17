import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/asis_colors.dart';
import '../../../core/version/actualizador_app.dart';
import '../../../core/version/version_app_api.dart';
import '../../../core/widgets/asiscole_logo.dart';

/// Pantalla a pantalla completa cuando el canal ya no admite esta versión.
/// No hay forma de saltarla: un cliente viejo dejaría de entender el contrato.
class ActualizacionObligatoriaPage extends StatefulWidget {
  const ActualizacionObligatoriaPage({required this.politica, super.key});

  final PoliticaVersion politica;

  @override
  State<ActualizacionObligatoriaPage> createState() =>
      _ActualizacionObligatoriaPageState();
}

class _ActualizacionObligatoriaPageState
    extends State<ActualizacionObligatoriaPage> {
  bool _trabajando = false;

  Future<void> _actualizar() async {
    setState(() => _trabajando = true);
    final resultado = await ActualizadorApp.intentar(
      politica: widget.politica,
      inmediata: true,
    );
    if (!mounted) return;
    setState(() => _trabajando = false);
    if (resultado == ResultadoActualizacion.pedirAlColegio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pide la versión nueva al colegio. Esta no se puede seguir usando.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mensaje = (widget.politica.mensaje ?? '').trim().isEmpty
        ? 'Esta versión de ${Env.nombreApp} ya no puede hablar con el colegio. '
            'Actualízala para seguir recibiendo los avisos.'
        : widget.politica.mensaje!;

    return Scaffold(
      backgroundColor: context.asis.fondo,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
          child: Column(
            children: [
              const AsiscoleLogo(size: 72),
              const SizedBox(height: 28),
              Text(
                'Actualización necesaria',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: context.asis.texto,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: context.asis.textoSecundario,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _trabajando ? null : _actualizar,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.asis.morado,
                  ),
                  child: _trabajando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Actualizar',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Si no aparece en Play Store, pide el archivo al colegio '
                '(${Env.correoSoporte}).',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: context.asis.textoSecundario,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
