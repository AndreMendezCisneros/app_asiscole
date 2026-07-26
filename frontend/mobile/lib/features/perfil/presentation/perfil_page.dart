import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injector.dart';
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
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
      appBar: AppBar(title: const Text('Perfil')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ListTile(
                      title: const Text('Teléfono'),
                      subtitle: Text(_telefono ?? ''),
                    ),
                    const Divider(),
                    Text('Estudiantes vinculados', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._hijos.map(
                      (e) => ListTile(
                        title: Text(e.nombre),
                        subtitle: Text('${e.grado} ${e.seccion} · ${e.colegio}'),
                        trailing: e.activo
                            ? const Icon(Icons.check_circle, color: Colors.teal)
                            : null,
                        onTap: () => _seleccionar(e),
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => context.read<AuthCubit>().cerrarSesion(),
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _eliminar,
                      child: const Text('Eliminar mi cuenta'),
                    ),
                  ],
                ),
    );
  }
}
