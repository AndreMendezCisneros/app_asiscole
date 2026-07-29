import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injector.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
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
    await sl<PerfilRepository>().seleccionarEstudiante(e.id);
    await _cargar();
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

  Future<void> _eliminar() async {
    final doc = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ConfirmarDocumentoDialog(),
    );
    if (doc == null || doc.isEmpty || !mounted) return;
    try {
      await sl<PerfilRepository>().eliminarCuenta(doc);
      if (!mounted) return;
      await context.read<AuthCubit>().cerrarSesion();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar la cuenta.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final alias = (_perfil?.alias ?? '').trim();
    return Scaffold(
      backgroundColor: AppTheme.fondo,
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
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.moradoPrincipal,
                          AppTheme.moradoSecundario,
                          AppTheme.moradoClaro,
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
                          child: const AsiscoleLogo(size: 64),
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
                            leading: const Icon(
                              Icons.badge_outlined,
                              color: AppTheme.moradoSecundario,
                            ),
                            title: Text(
                              alias.isEmpty ? 'Sin nombre' : alias,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.texto,
                              ),
                            ),
                            subtitle: const Text(
                              'Cómo te mostramos en la app',
                              style: TextStyle(
                                color: AppTheme.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.edit_outlined,
                              color: AppTheme.moradoSecundario,
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
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'No hay estudiantes vinculados',
                                style: TextStyle(
                                  color: AppTheme.textoSecundario,
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.texto,
                                  ),
                                ),
                                subtitle: Text(
                                  '${e.grado} ${e.seccion} · ${e.colegio}',
                                  style: const TextStyle(
                                    color: AppTheme.textoSecundario,
                                  ),
                                ),
                                trailing: e.activo
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: AppTheme.celeste,
                                      )
                                    : Icon(
                                        Icons.chevron_right,
                                        color: AppTheme.moradoSecundario
                                            .withValues(alpha: 0.7),
                                      ),
                                onTap: () => _seleccionar(e),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _CardGrupo(
                        titulo: 'Legal',
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.gavel_outlined,
                              color: AppTheme.moradoSecundario,
                            ),
                            title: const Text(
                              'Términos y condiciones',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.texto,
                              ),
                            ),
                            subtitle: Text(
                              _perfil?.terminosVersion == null
                                  ? 'Leer el documento'
                                  : 'Versión ${_perfil!.terminosVersion}',
                              style: const TextStyle(
                                color: AppTheme.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: AppTheme.moradoSecundario,
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
                            leading: const Icon(
                              Icons.menu_book_outlined,
                              color: AppTheme.moradoSecundario,
                            ),
                            title: const Text(
                              'Guía de uso',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.texto,
                              ),
                            ),
                            subtitle: const Text(
                              'Ver de nuevo los tips de cada sección',
                              style: TextStyle(
                                color: AppTheme.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: AppTheme.moradoSecundario,
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
                            leading: const Icon(
                              Icons.logout,
                              color: AppTheme.moradoSecundario,
                            ),
                            title: const Text(
                              'Cerrar sesión',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.texto,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: AppTheme.moradoSecundario,
                            ),
                            onTap: _confirmarCerrarSesion,
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
    return AlertDialog(
      title: const Text('Eliminar cuenta'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(
          labelText: 'Documento del estudiante',
          helperText: 'Confirma con el DNI/código de barras del estudiante',
        ),
        keyboardType: TextInputType.number,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Eliminar'),
        ),
      ],
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
            style: const TextStyle(
              color: AppTheme.texto,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.blanco,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.borde),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
