import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../perfil/data/perfil_repository.dart';
import '../data/asistencias_api.dart';

class AsistenciasPage extends StatefulWidget {
  const AsistenciasPage({super.key});

  @override
  State<AsistenciasPage> createState() => _AsistenciasPageState();
}

class _AsistenciasPageState extends State<AsistenciasPage> {
  List<DiaAsistencia>? _dias;
  String? _error;
  bool _cargando = true;
  late DateTime _mes = DateTime.now();

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
      final dias = await sl<AsistenciasApi>().mes(
        estudianteId: id,
        anio: _mes.year,
        mes: _mes.month,
      );
      setState(() {
        _dias = dias;
        _cargando = false;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Se necesita conexión para ver asistencias.';
        _cargando = false;
      });
    }
  }

  bool get _hayRegistrosReales =>
      _dias?.any((d) => d.horaEntrada != null || d.horaSalida != null) ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Asistencias ${_mes.month}/${_mes.year}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() => _mes = DateTime(_mes.year, _mes.month - 1));
              _cargar();
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() => _mes = DateTime(_mes.year, _mes.month + 1));
              _cargar();
            },
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: !_hayRegistrosReales
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Aún no hay llegadas ni salidas este mes '
                                  'en el colegio. Cuando el SIE registre una '
                                  'entrada, aparecerá aquí.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _dias!.length,
                          itemBuilder: (_, i) {
                            final d = _dias![i];
                            final tieneHoras =
                                d.horaEntrada != null || d.horaSalida != null;
                            if (!tieneHoras &&
                                d.estado != 'falta' &&
                                d.estado != 'a_tiempo' &&
                                d.estado != 'tarde') {
                              return const SizedBox.shrink();
                            }
                            return ListTile(
                              title: Text(d.fecha),
                              subtitle: Text(_etiqueta(d.estado)),
                              trailing: Text(
                                [
                                  if (d.horaEntrada != null) d.horaEntrada!,
                                  if (d.horaSalida != null) '– ${d.horaSalida}',
                                ].join(' '),
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  String _etiqueta(String estado) => switch (estado) {
        'a_tiempo' => 'A tiempo',
        'tarde' => 'Tarde',
        'falta' => 'Falta',
        _ => 'Sin registro',
      };
}
