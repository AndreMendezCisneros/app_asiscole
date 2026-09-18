import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/error/error_codes.dart';
import '../../../core/router/app_router.dart';
import '../../../core/storage/local_db.dart';
import '../../../core/theme/asis_colors.dart';
import '../../../core/theme/preferencia_tema.dart';
import '../../../core/util/formato.dart';
import '../../../core/widgets/asiscole_logo.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../../core/widgets/pantalla_carga_asiscole.dart';
import '../../../core/widgets/tour_asiscole.dart';
import '../../auth/domain/perfil.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../data/perfil_repository.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  List<EstudianteVinculado> _hijos = [];
  Perfil? _perfil;
  String? _error;
  bool _cargando = true;

  /// Hijo cuyo cambio está en curso; evita toques repetidos sin feedback.
  int? _cambiandoA;

  @override
  void initState() {
    super.initState();
    _cargar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TourAsiscole.mostrarSiCorresponde(
        context,
        seccion: 'perfil',
        titulo: GuiasTour.perfil.titulo,
        cuerpo: GuiasTour.perfil.cuerpo,
      );
    });
  }

  Future<void> _verGuiaDeNuevo() async {
    await TourAsiscole.resetearTodo();
    if (!mounted) return;
    await TourAsiscole.mostrarSiCorresponde(
      context,
      seccion: 'perfil',
      titulo: GuiasTour.perfil.titulo,
      cuerpo: GuiasTour.perfil.cuerpo,
      forzar: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Guía reiniciada. Al abrir cada sección verás el tip otra vez.',
        ),
      ),
    );
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final repo = sl<PerfilRepository>();
      final resultados = await Future.wait([
        repo.obtener(),
        repo.estudiantes(),
      ]);
      setState(() {
        _perfil = resultados[0] as Perfil;
        _hijos = resultados[1] as List<EstudianteVinculado>;
        _cargando = false;
      });
    } catch (_) {
      setState(() {
        _error = 'No se pudo cargar el perfil.';
        _cargando = false;
      });
    }
  }

  Future<void> _seleccionar(EstudianteVinculado e) async {
    if (_cambiandoA != null || e.activo) return;
    setState(() => _cambiandoA = e.id);
    try {
      await sl<PerfilRepository>().seleccionarEstudiante(e.id);
      await _cargar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar de hijo.')),
      );
    } finally {
      if (mounted) setState(() => _cambiandoA = null);
    }
  }

  String _telefonoEnmascarado(String? tel) {
    if (tel == null || tel.isEmpty) return '—';
    final d = TelefonoPeru.soloDigitos(tel);
    if (d.length < 4) return '••••';
    final visibles = d.substring(d.length - 3);
    return '+51 ${d[0]}•• ••• $visibles';
  }

  Future<void> _editarAlias() async {
    final actual = _perfil?.alias ?? '';
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => _AliasEditDialog(aliasInicial: actual),
    );
    if (nuevo == null || !mounted) return;
    try {
      final perfil = await sl<PerfilRepository>().actualizarAlias(nuevo);
      if (!mounted) return;
      setState(() => _perfil = perfil);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nombre actualizado.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el nombre.')),
      );
    }
  }

  Future<void> _confirmarCerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Dejarás de recibir avisos en este teléfono hasta que vuelvas a ingresar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AuthCubit>().cerrarSesion();
  }

  Future<void> _borrarMensajesGuardados() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar los mensajes de este teléfono?'),
        content: const Text(
          'Se borrará la copia guardada en el dispositivo. Los mensajes se '
          'volverán a descargar cuando tengas conexión.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await sl<LocalDb>().vaciar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensajes guardados borrados.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron borrar los mensajes.')),
      );
    }
  }

  Future<void> _eliminar() async {
    final doc = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ConfirmarDocumentoDialog(),
    );
    if (doc == null || doc.isEmpty || !mounted) return;
    try {
      await sl<PerfilRepository>().eliminarCuenta(doc);
      if (!mounted) return;
      // `cerrarSesion` borra los tokens y la caché local de mensajes.
      await context.read<AuthCubit>().cerrarSesion();
    } on ApiError catch (e) {
      if (!mounted) return;
      final texto = e.codigo == CodigosError.vinculoNoEncontrado
          ? 'El documento no coincide con tu cuenta. '
              'Revísalo o pide la baja por la página web.'
          : e.mensaje;
      _avisarBajaFallida(texto);
    } catch (_) {
      if (!mounted) return;
      _avisarBajaFallida(
        'No se pudo eliminar la cuenta. Inténtalo de nuevo o usa la página web.',
      );
    }
  }

  void _avisarBajaFallida(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        action: SnackBarAction(
          label: 'Ver página',
          onPressed: () {
            launchUrl(
              Uri.parse(Env.urlEliminarCuenta),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alias = (_perfil?.alias ?? '').trim();
    return Scaffold(
      backgroundColor: context.asis.fondo,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.perfil),
          if (_cargando)
            const PantallaCargaAsiscole(mensaje: 'Cargando tu perfil…')
          else if (_error != null)
            Center(child: Text(_error!))
          else
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      MediaQuery.paddingOf(context).top + 28,
                      24,
                      32,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          context.asis.morado,
                          context.asis.moradoSecundario,
                          context.asis.moradoClaro,
                        ],
                      ),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const AsiscoleLogo(size: 64, conFondo: true),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          alias.isEmpty ? 'Mi perfil' : alias,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _telefonoEnmascarado(_perfil?.telefono),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _CardGrupo(
                        titulo: 'Tu nombre',
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.badge_outlined,
                              color: context.asis.moradoSecundario,
                            ),
                            title: Text(
                              alias.isEmpty ? 'Sin nombre' : alias,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: context.asis.texto,
                              ),
                            ),
                            subtitle: Text(
                              'Cómo te mostramos en la app',
                              style: TextStyle(
                                color: context.asis.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Icon(
                              Icons.edit_outlined,
                              color: context.asis.moradoSecundario,
                            ),
                            onTap: _editarAlias,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CardGrupo(
                        titulo: 'Estudiantes vinculados',
                        children: [
                          if (_hijos.isEmpty)
                            Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'No hay estudiantes vinculados',
                                style: TextStyle(
                                  color: context.asis.textoSecundario,
                                ),
                              ),
                            )
                          else
                            ..._hijos.map(
                              (e) => ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  e.nombre,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: context.asis.texto,
                                  ),
                                ),
                                subtitle: Text(
                                  '${e.grado} ${e.seccion} · ${e.colegio}',
                                  style: TextStyle(
                                    color: context.asis.textoSecundario,
                                  ),
                                ),
                                trailing: _cambiandoA == e.id
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : e.activo
                                        ? Icon(
                                            Icons.check_circle,
                                            color: context.asis.celeste,
                                          )
                                        : Icon(
                                            Icons.chevron_right,
                                            color: context.asis.moradoSecundario
                                                .withValues(alpha: 0.7),
                                          ),
                                onTap: () => _seleccionar(e),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CardGrupo(
                        titulo: 'Apariencia',
                        children: [_SelectorTema()],
                      ),
                      const SizedBox(height: 14),
                      _CardGrupo(
                        titulo: 'Legal',
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.gavel_outlined,
                              color: context.asis.moradoSecundario,
                            ),
                            title: Text(
                              'Términos y condiciones',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.asis.texto,
                              ),
                            ),
                            subtitle: Text(
                              _perfil?.terminosVersion == null
                                  ? 'Leer el documento'
                                  : 'Versión ${_perfil!.terminosVersion}',
                              style: TextStyle(
                                color: context.asis.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: context.asis.moradoSecundario,
                            ),
                            onTap: () => context.push(
                              Rutas.terminos,
                              extra: _perfil?.terminosAceptadosEn,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CardGrupo(
                        titulo: 'Ayuda',
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.menu_book_outlined,
                              color: context.asis.moradoSecundario,
                            ),
                            title: Text(
                              'Guía de uso',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.asis.texto,
                              ),
                            ),
                            subtitle: Text(
                              'Ver de nuevo los tips de cada sección',
                              style: TextStyle(
                                color: context.asis.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: context.asis.moradoSecundario,
                            ),
                            onTap: _verGuiaDeNuevo,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CardGrupo(
                        titulo: 'Cuenta',
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.logout,
                              color: context.asis.moradoSecundario,
                            ),
                            title: Text(
                              'Cerrar sesión',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.asis.texto,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: context.asis.moradoSecundario,
                            ),
                            onTap: _confirmarCerrarSesion,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(
                              Icons.cleaning_services_outlined,
                              color: context.asis.moradoSecundario,
                            ),
                            title: Text(
                              'Borrar mensajes guardados en este teléfono',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.asis.texto,
                              ),
                            ),
                            subtitle: Text(
                              'Borra la copia local; no afecta al colegio',
                              style: TextStyle(
                                color: context.asis.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: context.asis.moradoSecundario,
                            ),
                            onTap: _borrarMensajesGuardados,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(
                              'Eliminar mi cuenta',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onTap: _eliminar,
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AliasEditDialog extends StatefulWidget {
  const _AliasEditDialog({required this.aliasInicial});

  final String aliasInicial;

  @override
  State<_AliasEditDialog> createState() => _AliasEditDialogState();
}

class _AliasEditDialogState extends State<_AliasEditDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.aliasInicial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tu nombre'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 128,
        decoration: const InputDecoration(
          labelText: 'Nombre para mostrar',
          hintText: 'Ej. María',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ConfirmarDocumentoDialog extends StatefulWidget {
  const _ConfirmarDocumentoDialog();

  @override
  State<_ConfirmarDocumentoDialog> createState() =>
      _ConfirmarDocumentoDialogState();
}

class _ConfirmarDocumentoDialogState extends State<_ConfirmarDocumentoDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Eliminar mi cuenta'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta acción no se puede deshacer.',
              style: TextStyle(fontWeight: FontWeight.w700, color: error),
            ),
            const SizedBox(height: 10),
            Text(
              'Dejarás de recibir los avisos del colegio en este teléfono.\n'
              'Se cerrará tu sesión y se borrarán los mensajes guardados.\n'
              'Para volver a recibirlos tendrás que registrarte de nuevo.',
              style: TextStyle(color: context.asis.textoSecundario, height: 1.4),
            ),
            const SizedBox(height: 10),
            Text(
              'El expediente del estudiante en el colegio no se modifica.',
              style: TextStyle(color: context.asis.textoSecundario, fontSize: 12),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                labelText: 'Documento del estudiante',
                helperText: 'Confirma con el DNI/código de barras del estudiante',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: error),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Eliminar mi cuenta'),
        ),
      ],
    );
  }
}

/// Tres opciones de tema. Automático sigue al sistema y es el valor de fábrica.
class _SelectorTema extends StatelessWidget {
  static const _opciones = <(ThemeMode, IconData, String, String)>[
    (
      ThemeMode.system,
      Icons.brightness_auto_outlined,
      'Automático',
      'Igual que el teléfono',
    ),
    (ThemeMode.light, Icons.light_mode_outlined, 'Claro', ''),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Oscuro', ''),
  ];

  @override
  Widget build(BuildContext context) {
    final preferencia = sl<PreferenciaTema>();
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: preferencia.modo,
      builder: (context, actual, _) => Column(
        children: [
          for (final (modo, icono, titulo, detalle) in _opciones) ...[
            if (modo != _opciones.first.$1) const Divider(height: 1),
            ListTile(
              leading: Icon(icono, color: context.asis.moradoSecundario),
              title: Text(
                titulo,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.asis.texto,
                ),
              ),
              subtitle: detalle.isEmpty
                  ? null
                  : Text(
                      detalle,
                      style: TextStyle(
                        color: context.asis.textoSecundario,
                        fontSize: 12,
                      ),
                    ),
              trailing: modo == actual
                  ? Icon(Icons.check_circle, color: context.asis.celeste)
                  : null,
              onTap: () => preferencia.cambiar(modo),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardGrupo extends StatelessWidget {
  const _CardGrupo({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            titulo,
            style: TextStyle(
              color: context.asis.texto,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.asis.superficie,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.asis.borde),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
