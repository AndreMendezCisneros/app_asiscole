import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/util/formato.dart';
import '../../../core/widgets/asiscole_logo.dart';
import '../../../core/widgets/fondo_asiscole.dart';
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

  static const _radioCampo = BorderRadius.all(Radius.circular(18));

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

  InputDecoration _decoCampo({
    required String hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppTheme.textoSecundario.withValues(alpha: 0.7),
      ),
      filled: true,
      fillColor: AppTheme.blanco,
      prefixIcon: prefix,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: _radioCampo,
        borderSide: const BorderSide(color: AppTheme.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _radioCampo,
        borderSide: const BorderSide(color: AppTheme.borde),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: _radioCampo,
        borderSide: BorderSide(color: AppTheme.moradoPrincipal, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _radioCampo,
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _radioCampo,
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.blanco,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.login),
          SafeArea(
            child: BlocBuilder<AuthCubit, AuthState>(
              builder: (context, estado) {
                final cargando = estado is Authenticating;
                final fallo = estado is Unauthenticated ? estado : null;

                return AbsorbPointer(
                  absorbing: cargando,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                    child: Form(
                      key: _formulario,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppTheme.blanco,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.moradoPrincipal
                                        .withValues(alpha: 0.12),
                                    blurRadius: 28,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: const AsiscoleLogo(size: 96),
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            '¡Bienvenido! 👋',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.texto,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Ingresa tus datos para recibir los avisos\n'
                            'del colegio en Asiscole Messenger',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: AppTheme.textoSecundario,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.fondo,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: AppTheme.borde),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 16,
                                    color: AppTheme.moradoPrincipal,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Canal seguro del apoderado',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.moradoPrincipal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (fallo?.mensaje != null) ...[
                            PanelAviso(
                              texto: fallo!.mensaje!,
                              tono: TonoAviso.error,
                            ),
                            const SizedBox(height: 18),
                          ],
                          const _EtiquetaCampo('Teléfono del apoderado'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _telefono,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [FormateadorTelefonoPeru()],
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            style: const TextStyle(
                              color: AppTheme.texto,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            decoration: _decoCampo(
                              hint: '987 654 321',
                              prefix: IgnorePointer(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 16,
                                    right: 6,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.moradoClaro
                                              .withValues(alpha: 0.18),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          TelefonoPeru.prefijo,
                                          style: TextStyle(
                                            color: AppTheme.moradoPrincipal,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            validator: (valor) =>
                                TelefonoPeru.esValido(valor ?? '')
                                    ? null
                                    : 'Ingresa los 9 dígitos de tu celular.',
                          ),
                          const SizedBox(height: 18),
                          const _EtiquetaCampo('Documento del estudiante'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _documento,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(50),
                            ],
                            style: const TextStyle(
                              color: AppTheme.texto,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            decoration: _decoCampo(
                              hint: '70123456',
                              prefix: const Icon(
                                Icons.badge_outlined,
                                color: AppTheme.moradoSecundario,
                              ),
                            ),
                            onFieldSubmitted: (_) => _enviar(),
                            validator: (valor) =>
                                (valor == null || valor.trim().length < 4)
                                    ? 'Ingresa el documento del estudiante.'
                                    : null,
                          ),
                          const SizedBox(height: 28),
                          _BotonIngresar(
                            cargando: cargando,
                            onPressed: cargando ? null : _enviar,
                          ),
                          const SizedBox(height: 24),
                          const PanelAviso(
                            titulo: 'Estos datos los registra el colegio',
                            texto:
                                'Usa el número de celular que dejaste como contacto y el '
                                'documento con el que el colegio identifica al estudiante. '
                                'Si no coinciden, comunícate con la institución.',
                            icono: Icons.help_outline,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Solo recibes avisos: este canal no permite responder '
                            'ni escribir al colegio.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppTheme.textoSecundario,
                                  height: 1.4,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaCampo extends StatelessWidget {
  const _EtiquetaCampo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textoSecundario,
      ),
    );
  }
}

class _BotonIngresar extends StatelessWidget {
  const _BotonIngresar({required this.cargando, required this.onPressed});

  final bool cargando;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.moradoPrincipal,
            AppTheme.moradoSecundario,
            AppTheme.moradoClaro,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.moradoPrincipal.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: 56,
            child: Center(
              child: cargando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Ingresar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
