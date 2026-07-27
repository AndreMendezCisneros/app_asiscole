import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/formato.dart';
import '../../../core/widgets/asiscole_logo.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../data/perfil_repository.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  List<EstudianteVinculado> _hijos = [];
  String? _telefono;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final repo = sl<PerfilRepository>();
      final perfil = await repo.obtener();
      final hijos = await repo.estudiantes();
      setState(() {
        _telefono = perfil.telefono;
        _hijos = hijos;
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

  Future<void> _eliminar() async {
    final doc = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Eliminar cuenta'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Documento del estudiante',
              helperText: 'Confirma con el DNI/código de barras del estudiante',
            ),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
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
    return Scaffold(
      backgroundColor: AppTheme.fondo,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.perfil),
          if (_cargando)
            const Center(child: CircularProgressIndicator())
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
                            const Text(
                              'Mi perfil',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _telefonoEnmascarado(_telefono),
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
                                onTap: () =>
                                    context.read<AuthCubit>().cerrarSesion(),
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
