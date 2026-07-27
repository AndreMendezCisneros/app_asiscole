import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/error_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/encabezado_asiscole.dart';
import '../../../core/widgets/panel_aviso.dart';
import 'auth_cubit.dart';

/// Se abre desde el push en el dispositivo que **tiene** la sesión activa.
class AprobarTransferenciaPage extends StatefulWidget {
  const AprobarTransferenciaPage({super.key, required this.idSolicitud});

  final String idSolicitud;

  @override
  State<AprobarTransferenciaPage> createState() =>
      _AprobarTransferenciaPageState();
}

class _AprobarTransferenciaPageState extends State<AprobarTransferenciaPage> {
  bool _enviando = false;
  String? _codigoError;
  bool _rechazada = false;

  Future<void> _resolver({required bool aprobar}) async {
    setState(() {
      _enviando = true;
      _codigoError = null;
    });

    final cubit = context.read<AuthCubit>();
    final codigo = aprobar
        ? await cubit.aprobarTransferenciaEntrante(widget.idSolicitud)
        : await cubit.rechazarTransferenciaEntrante(widget.idSolicitud);

    if (!mounted) return;
    setState(() {
      _enviando = false;
      _codigoError = codigo;
      _rechazada = codigo == null && !aprobar;
    });

    // Al aprobar, el cubit pasa a `Unauthenticated` y el router lleva al login.
    if (codigo == null && !aprobar && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.fondo,
      appBar: AppBar(title: const Text('Solicitud de acceso')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EncabezadoAsiscole(
                icono: Icons.devices_other_outlined,
                titulo: '¿Permitir el inicio de sesión en otro dispositivo?',
                subtitulo:
                    'Alguien está intentando entrar a tu cuenta de Asiscole desde '
                    'otro equipo. Solo aprueba si fuiste tú.',
              ),
              const SizedBox(height: 28),
              const PanelAviso(
                titulo: 'Al aprobar, se cerrará la sesión en este equipo',
                texto:
                    'Este dispositivo dejará de recibir avisos hasta que vuelvas a '
                    'iniciar sesión. Los mensajes ya descargados seguirán disponibles.',
                tono: TonoAviso.advertencia,
              ),
              if (_codigoError != null) ...[
                const SizedBox(height: 20),
                PanelAviso(
                  texto: CodigosError.mensajePorDefecto(_codigoError!),
                  tono: TonoAviso.error,
                ),
              ],
              if (_rechazada) ...[
                const SizedBox(height: 20),
                const PanelAviso(
                  texto: 'Rechazaste la solicitud. Tu sesión sigue activa aquí.',
                  tono: TonoAviso.exito,
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _enviando ? null : () => _resolver(aprobar: true),
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Aprobar y cerrar sesión aquí'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _enviando ? null : () => _resolver(aprobar: false),
                icon: const Icon(Icons.block_outlined),
                label: const Text('Rechazar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
