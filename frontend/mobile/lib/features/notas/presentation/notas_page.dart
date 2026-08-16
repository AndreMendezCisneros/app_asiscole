import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/push/servicio_push.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/chip_hijo_activo.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../../core/widgets/pantalla_carga_asiscole.dart';
import '../../../core/widgets/selector_hijo_sheet.dart';
import '../../../core/widgets/tour_asiscole.dart';
import '../../auth/domain/perfil.dart';
import '../../perfil/data/perfil_repository.dart';
import '../data/notas_api.dart';

/// Historial de notas semanales del hijo activo (ingesta `tipo: nota`).
class NotasPage extends StatefulWidget {
  const NotasPage({super.key});

  @override
  State<NotasPage> createState() => _NotasPageState();
}

class _NotasPageState extends State<NotasPage> with CierraSheetAlCambiarTab {
  List<NotaSemanal>? _items;
  String? _error;
  bool _cargando = true;
  bool _activo = false;
  EstudianteVinculado? _hijo;
  int? _estudianteId;
  int _epochVisto = 0;
  StreamSubscription<void>? _avisos;

  @override
  String get rutaDeEstaSeccion => '/notas';

  @override
  void initState() {
    super.initState();
    final repo = sl<PerfilRepository>();
    _epochVisto = repo.estudianteActivoEpoch.value;
    repo.estudianteActivoEpoch.addListener(_onEstudianteActivoCambio);
    _avisos = sl<ServicioPush>().avisosDeNota.listen((_) {
      if (mounted) unawaited(_cargar());
    });
    unawaited(_cargar());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) registrarListenerRuta();
      if (!mounted) return;
      TourAsiscole.mostrarSiCorresponde(
        context,
        seccion: 'notas',
        titulo: GuiasTour.notas.titulo,
        cuerpo: GuiasTour.notas.cuerpo,
      );
    });
  }

  @override
  void dispose() {
    sl<PerfilRepository>()
        .estudianteActivoEpoch
        .removeListener(_onEstudianteActivoCambio);
    _avisos?.cancel();
    cancelarListenerRuta();
    super.dispose();
  }

  void _onEstudianteActivoCambio() {
    final epoch = sl<PerfilRepository>().estudianteActivoEpoch.value;
    if (epoch == _epochVisto) return;
    _epochVisto = epoch;
    if (!mounted) return;
    unawaited(_cargar());
  }

  Future<void> _cambiarHijoDesdeChip() async {
    await mostrarSelectorHijo(
      context: context,
      estudianteActivoId: _estudianteId,
    );
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final flags = sl<FeatureFlags>();
      await flags.refrescar(forzar: true);
      final activo = flags.notas.value;
      if (!activo) {
        if (!mounted) return;
        setState(() {
          _activo = false;
          _items = const [];
          _cargando = false;
        });
        return;
      }

      final repo = sl<PerfilRepository>();
      final resultados = await Future.wait([
        repo.obtener(forzar: true),
        repo.estudiantes(forzar: true),
      ]);
      final perfil = resultados[0] as Perfil;
      final hijos = resultados[1] as List<EstudianteVinculado>;
      final id = perfil.estudianteActivoId;
      EstudianteVinculado? hijo;
      for (final h in hijos) {
        if (h.id == id) {
          hijo = h;
          break;
        }
      }
      if (hijo == null) {
        for (final h in hijos) {
          if (h.activo) {
            hijo = h;
            break;
          }
        }
        hijo ??= hijos.isEmpty ? null : hijos.first;
      }

      if (mounted) {
        setState(() {
          _activo = true;
          _hijo = hijo;
          _estudianteId = id;
        });
      }
      if (id == null) {
        setState(() {
          _error = 'Selecciona un estudiante en Perfil.';
          _cargando = false;
        });
        return;
      }
      final items = await sl<NotasApi>().listar(id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _cargando = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _activo = true;
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activo = true;
        _error = 'No se pudieron cargar las notas. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.fondo,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.notas),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Notas',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.texto,
                        ),
                  ),
                ),
                if (_hijo != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: ChipHijoActivo(
                      nombre: _hijo!.nombre,
                      detalle: '${_hijo!.grado} ${_hijo!.seccion}'.trim(),
                      onCambiar: () => unawaited(_cambiarHijoDesdeChip()),
                    ),
                  ),
                Expanded(child: _cuerpo()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const PantallaCargaAsiscole(mensaje: 'Cargando notas…');
    }
    if (!_activo) {
      return const EmptyStateAsiscole(
        mensaje:
            'Próximamente\nLas notas se activarán sin una nueva versión.',
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.texto,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: (_items ?? const []).isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                EmptyStateAsiscole(
                  mensaje: 'Aún no hay notas de este hijo',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _items!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _CardNota(item: _items![i]),
            ),
    );
  }
}

class _CardNota extends StatelessWidget {
  const _CardNota({required this.item});

  final NotaSemanal item;

  @override
  Widget build(BuildContext context) {
    final carrera = (item.carrera ?? '').trim();
    final area = (item.areaNombre ?? '').trim();
    return Material(
      color: AppTheme.blanco,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.borde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.moradoClaro.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.nota,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.moradoPrincipal,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                      Text(
                        '/ ${item.notaMaxima?.trim().isNotEmpty == true ? item.notaMaxima : '20'}',
                        style: const TextStyle(
                          color: AppTheme.moradoSecundario,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.tituloSemana,
                        style: const TextStyle(
                          color: AppTheme.texto,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (item.rangoFechas.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.rangoFechas,
                          style: const TextStyle(
                            color: AppTheme.textoSecundario,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.borde),
            const SizedBox(height: 10),
            if (carrera.isNotEmpty) _DatoNota(etiqueta: 'Carrera', valor: carrera),
            if (area.isNotEmpty) _DatoNota(etiqueta: 'Área', valor: area),
            if (item.fechaRegistro.isNotEmpty)
              _DatoNota(etiqueta: 'Registrada', valor: item.fechaRegistro),
            if (carrera.isEmpty && area.isEmpty && item.rangoFechas.isEmpty)
              const Text(
                'Nota semanal del colegio',
                style: TextStyle(
                  color: AppTheme.textoSecundario,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DatoNota extends StatelessWidget {
  const _DatoNota({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              etiqueta,
              style: const TextStyle(
                color: AppTheme.textoSecundario,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                color: AppTheme.texto,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
