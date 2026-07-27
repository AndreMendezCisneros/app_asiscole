import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/encabezado_asiscole.dart';
import '../../../core/widgets/panel_aviso.dart';
import 'auth_cubit.dart';
import 'auth_state.dart';

/// 403 ACCOUNT_SUSPENDED. Los tokens ya se borraron; la caché de mensajes no.
class CuentaSuspendidaPage extends StatelessWidget {
  const CuentaSuspendidaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.fondo,
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, estado) {
            final motivo = estado is Suspended ? estado.motivo : null;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EncabezadoAsiscole(
                    icono: Icons.lock_outline,
                    titulo: 'Tu cuenta está suspendida',
                    subtitulo:
                        'Mientras dure la suspensión no podrás recibir avisos nuevos '
                        'del colegio en este canal.',
                  ),
                  const SizedBox(height: 28),
                  if (motivo != null && motivo.isNotEmpty)
                    PanelAviso(
                      titulo: 'Motivo indicado por el colegio',
                      texto: motivo,
                      tono: TonoAviso.error,
                    ),
                  const SizedBox(height: 20),
                  const PanelAviso(
                    titulo: '¿Cómo reactivarla?',
                    texto:
                        'Comunícate con la secretaría o la dirección del colegio. '
                        'Solo el personal autorizado puede reactivar la cuenta.',
                    icono: Icons.support_agent_outlined,
                  ),
                  const SizedBox(height: 20),
                  const PanelAviso(
                    texto:
                        'Los mensajes que ya habías recibido siguen guardados en este '
                        'dispositivo y puedes consultarlos sin conexión.',
                    tono: TonoAviso.informacion,
                    icono: Icons.inbox_outlined,
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: () => context.read<AuthCubit>().volverALogin(),
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
