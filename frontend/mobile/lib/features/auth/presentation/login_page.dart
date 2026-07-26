import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/util/formato.dart';
import '../../../core/widgets/encabezado_asiscole.dart';
import '../../../core/widgets/panel_aviso.dart';
import 'auth_cubit.dart';
import 'auth_state.dart';

/// Ingreso del apoderado con su teléfono y el documento del estudiante.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formulario = GlobalKey<FormState>();
  final _telefono = TextEditingController();
  final _documento = TextEditingController();

  @override
  void dispose() {
    _telefono.dispose();
    _documento.dispose();
    super.dispose();
  }

  void _enviar() {
    FocusScope.of(context).unfocus();
    if (!(_formulario.currentState?.validate() ?? false)) return;
    context.read<AuthCubit>().iniciarSesion(
          telefono: TelefonoPeru.aE164(_telefono.text),
          documentoEstudiante: _documento.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, estado) {
            final cargando = estado is Authenticating;
            final fallo = estado is Unauthenticated ? estado : null;

            return AbsorbPointer(
              absorbing: cargando,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                child: Form(
                  key: _formulario,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const EncabezadoAsiscole(
                        titulo: 'Asiscole Messenger',
                        subtitulo:
                            'Recibe aquí los avisos de entradas, salidas e '
                            'incidencias de tu hijo o hija.',
                      ),
                      const SizedBox(height: 32),
                      if (fallo?.mensaje != null) ...[
                        PanelAviso(
                          texto: fallo!.mensaje!,
                          tono: TonoAviso.error,
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text(
                        'Teléfono del apoderado',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _telefono,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [FormateadorTelefonoPeru()],
                        autofillHints: const [AutofillHints.telephoneNumber],
                        decoration: InputDecoration(
                          hintText: '987 654 321',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 16, right: 8),
                            child: Text(
                              TelefonoPeru.prefijo,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: esquema.onSurfaceVariant),
                            ),
                          ),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        validator: (valor) => TelefonoPeru.esValido(valor ?? '')
                            ? null
                            : 'Ingresa los 9 dígitos de tu celular.',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Documento del estudiante',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _documento,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [LengthLimitingTextInputFormatter(50)],
                        decoration: const InputDecoration(
                          hintText: '70123456',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        onFieldSubmitted: (_) => _enviar(),
                        validator: (valor) =>
                            (valor == null || valor.trim().length < 4)
                                ? 'Ingresa el documento del estudiante.'
                                : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: cargando ? null : _enviar,
                        child: cargando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Ingresar'),
                      ),
                      const SizedBox(height: 28),
                      const PanelAviso(
                        titulo: 'Estos datos los registra el colegio',
                        texto:
                            'Usa el número de celular que dejaste como contacto y el '
                            'documento con el que el colegio identifica al estudiante. '
                            'Si no coinciden, comunícate con la institución.',
                        icono: Icons.help_outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Solo recibes avisos: este canal no permite responder ni '
                        'escribir al colegio.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: esquema.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
