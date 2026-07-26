import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/util/formato.dart';
import '../../../core/widgets/encabezado_asiscole.dart';
import '../../../core/widgets/panel_aviso.dart';
import 'auth_cubit.dart';
import 'auth_state.dart';

/// Espera de la respuesta del dispositivo activo, con cuenta regresiva de
/// 5 minutos. El cubit sondea el estado; si pasa a `approved` reintenta el
/// login solo, y si es `rejected` o `expired` vuelve al inicio de sesión.
class EsperandoAprobacionPage extends StatefulWidget {
  const EsperandoAprobacionPage({super.key});

  @override
  State<EsperandoAprobacionPage> createState() =>
      _EsperandoAprobacionPageState();
}

class _EsperandoAprobacionPageState extends State<EsperandoAprobacionPage> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    context.read<AuthCubit>().iniciarSondeoTransferencia();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, estado) {
            if (estado is! AwaitingTransferApproval) {
              return const Center(child: CircularProgressIndicator());
            }

            final restante = estado.solicitud.restante;
            final agotado = restante == Duration.zero;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EncabezadoAsiscole(
                    icono: Icons.hourglass_top_outlined,
                    titulo: 'Esperando la aprobación',
                    subtitulo:
                        'Enviamos una notificación al dispositivo que tiene la '
                        'sesión abierta. Mantén esta pantalla abierta.',
                  ),
                  const SizedBox(height: 36),
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 132,
                          height: 132,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox.expand(
                                child: CircularProgressIndicator(
                                  value: agotado
                                      ? 0
                                      : restante.inSeconds /
                                          const Duration(minutes: 5).inSeconds,
                                  strokeWidth: 8,
                                  backgroundColor: esquema.surfaceContainerHighest,
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    FechasLima.cuentaRegresiva(restante),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    'restantes',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  PanelAviso(
                    titulo: agotado ? 'Tiempo agotado' : 'Solicitud enviada',
                    texto: agotado
                        ? 'La solicitud está por vencer. Si nadie responde, vuelve a '
                            'intentarlo o pide al colegio que cierre la sesión anterior.'
                        : 'Cuando el otro dispositivo apruebe el acceso, entrarás '
                            'automáticamente. Si lo rechaza, te lo avisaremos aquí.',
                    tono: agotado ? TonoAviso.advertencia : TonoAviso.informacion,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () => context.read<AuthCubit>().volverALogin(),
                    child: const Text('Cancelar y volver'),
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
