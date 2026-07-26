import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/error_codes.dart';
import '../../../core/widgets/encabezado_asiscole.dart';
import '../../../core/widgets/panel_aviso.dart';
import 'auth_cubit.dart';
import 'auth_state.dart';

/// 409 SESSION_ALREADY_ACTIVE: la cuenta ya tiene sesión en otro dispositivo.
///
/// No es un error seco: se ofrece pedir el traspaso a este equipo.
class SesionDenegadaPage extends StatelessWidget {
  const SesionDenegadaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, estado) {
            if (estado is! LoginDenied) {
              return const Center(child: CircularProgressIndicator());
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EncabezadoAsiscole(
                    icono: Icons.phonelink_lock_outlined,
                    titulo: 'Tu cuenta ya tiene una sesión abierta',
                    subtitulo:
                        'Asiscole permite una sola sesión activa por cuenta, para '
                        'proteger la información del estudiante.',
                  ),
                  const SizedBox(height: 28),
                  PanelAviso(texto: estado.mensaje, icono: Icons.devices_other),
                  const SizedBox(height: 24),
                  Text(
                    '¿Qué puedes hacer?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  const _Paso(
                    numero: '1',
                    texto:
                        'Pedir el acceso desde aquí. El otro dispositivo recibirá una '
                        'notificación y tendrá 5 minutos para aprobarla o rechazarla.',
                  ),
                  const SizedBox(height: 12),
                  const _Paso(
                    numero: '2',
                    texto:
                        'Si ya no tienes el otro equipo a la mano, comunícate con el '
                        'colegio para que cierre la sesión anterior.',
                  ),
                  const SizedBox(height: 28),
                  if (estado.errorSolicitud != null) ...[
                    PanelAviso(
                      texto: CodigosError.mensajePorDefecto(
                        estado.errorSolicitud!,
                      ),
                      tono: TonoAviso.error,
                    ),
                    const SizedBox(height: 20),
                  ],
                  FilledButton.icon(
                    onPressed: estado.solicitando
                        ? null
                        : () =>
                            context.read<AuthCubit>().solicitarTransferencia(),
                    icon: estado.solicitando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_to_mobile_outlined),
                    label: const Text('Solicitar acceso en este dispositivo'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: estado.solicitando
                        ? null
                        : () => context.read<AuthCubit>().volverALogin(),
                    child: const Text('Volver al inicio de sesión'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.numero, required this.texto});

  final String numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: esquema.primaryContainer,
          child: Text(
            numero,
            style: TextStyle(
              color: esquema.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(height: 1.4, color: esquema.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
