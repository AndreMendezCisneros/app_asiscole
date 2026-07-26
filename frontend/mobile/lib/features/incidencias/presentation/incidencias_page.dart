import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../perfil/data/perfil_repository.dart';
import '../data/incidencias_api.dart';

class IncidenciasPage extends StatefulWidget {
  const IncidenciasPage({super.key});

  @override
  State<IncidenciasPage> createState() => _IncidenciasPageState();
}

class _IncidenciasPageState extends State<IncidenciasPage> {
  List<IncidenciaResumen>? _items;
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
      final perfil = await sl<PerfilRepository>().obtener();
      final id = perfil.estudianteActivoId;
      if (id == null) {
        setState(() {
          _error = 'Selecciona un estudiante en Perfil.';
          _cargando = false;
        });
        return;
      }
      final items = await sl<IncidenciasApi>().listar(id);
      setState(() {
        _items = items;
        _cargando = false;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Se necesita conexión para ver incidencias.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incidencias')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: _items!.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No hay incidencias registradas')),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _items!.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final it = _items![i];
                            return ListTile(
                              title: Text(it.falta),
                              subtitle: Text('${it.categoria} · ${it.reportadoPor}'),
                              trailing: it.esGrave
                                  ? const Chip(label: Text('Grave'))
                                  : null,
                            );
                          },
                        ),
                ),
    );
  }
}
