import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/push/servicio_push.dart';
import '../../../core/theme/asis_colors.dart';
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
  bool _sinConexion = false;
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
    // Otro hijo: lo ya pintado no le pertenece.
    setState(() => _items = null);
    unawaited(_cargar(forzar: true));
  }

  Future<void> _cambiarHijoDesdeChip() async {
    await mostrarSelectorHijo(
      context: context,
      estudianteActivoId: _estudianteId,
    );
  }

  /// [forzar] solo con motivo: cambio de hijo o pull-to-refresh. En cada
  /// entrada a la pestaña bastan los datos ya conocidos.
  Future<void> _cargar({bool forzar = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
      _sinConexion = false;
    });
    try {
      final flags = sl<FeatureFlags>();
      await flags.refrescar(forzar: forzar);
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
        repo.obtener(forzar: forzar),
        repo.estudiantes(forzar: forzar),
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
        _sinConexion = e.esSinConexion;
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
      backgroundColor: context.asis.fondo,
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
                          color: context.asis.texto,
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
    if (_sinConexion) {
      // Las notas se consultan en el momento: sin red no hay nada que mostrar,
      // pero conviene decir que es la conexión y no que la sección esté vacía.
      return EmptyStateAsiscole(
        mensaje: 'Sin conexión\nLas notas se consultan al colegio, '
            'así que necesitas internet para verlas.',
        mostrarLogo: false,
        etiquetaReintentar: 'Reintentar',
        onReintentar: () => unawaited(_cargar(forzar: true)),
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
                style: TextStyle(
                  color: context.asis.texto,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => unawaited(_cargar(forzar: true)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _cargar(forzar: true),
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
      color: context.asis.superficie,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.asis.borde),
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
                    color: context.asis.moradoClaro.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.nota,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.asis.morado,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                      Text(
                        '/ ${item.notaMaxima?.trim().isNotEmpty == true ? item.notaMaxima : '20'}',
                        style: TextStyle(
                          color: context.asis.moradoSecundario,
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
                        style: TextStyle(
                          color: context.asis.texto,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (item.rangoFechas.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.rangoFechas,
                          style: TextStyle(
                            color: context.asis.textoSecundario,
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
            Divider(height: 1, color: context.asis.borde),
            const SizedBox(height: 10),
            if (carrera.isNotEmpty) _DatoNota(etiqueta: 'Carrera', valor: carrera),
            if (area.isNotEmpty) _DatoNota(etiqueta: 'Área', valor: area),
            if (item.fechaRegistro.isNotEmpty)
              _DatoNota(etiqueta: 'Registrada', valor: item.fechaRegistro),
            if (carrera.isEmpty && area.isEmpty && item.rangoFechas.isEmpty)
              Text(
                'Nota semanal del colegio',
                style: TextStyle(
                  color: context.asis.textoSecundario,
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
              style: TextStyle(
                color: context.asis.textoSecundario,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                color: context.asis.texto,
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
