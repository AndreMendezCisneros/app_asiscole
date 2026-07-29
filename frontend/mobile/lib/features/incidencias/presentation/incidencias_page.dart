import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/error/error_codes.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/chip_hijo_activo.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../../core/widgets/pantalla_carga_asiscole.dart';
import '../../../core/widgets/selector_hijo_sheet.dart';
import '../../../core/widgets/tour_asiscole.dart';
import '../../auth/domain/perfil.dart';
import '../../perfil/data/perfil_repository.dart';
import '../data/incidencias_api.dart';

class IncidenciasPage extends StatefulWidget {
  const IncidenciasPage({super.key});

  @override
  State<IncidenciasPage> createState() => _IncidenciasPageState();
}

class _IncidenciasPageState extends State<IncidenciasPage>
    with CierraSheetAlCambiarTab {
  List<IncidenciaResumen>? _items;
  String? _error;
  bool _cargando = true;
  EstudianteVinculado? _hijo;
  int? _estudianteId;
  bool _citacionActiva = false;
  int _epochVisto = 0;

  @override
  String get rutaDeEstaSeccion => '/incidencias';

  @override
  void initState() {
    super.initState();
    final repo = sl<PerfilRepository>();
    _epochVisto = repo.estudianteActivoEpoch.value;
    repo.estudianteActivoEpoch.addListener(_onEstudianteActivoCambio);
    _cargar();
    unawaited(_cargarFlagCitacion());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) registrarListenerRuta();
      if (!mounted) return;
      TourAsiscole.mostrarSiCorresponde(
        context,
        seccion: 'incidencias',
        titulo: GuiasTour.incidencias.titulo,
        cuerpo: GuiasTour.incidencias.cuerpo,
      );
    });
  }

  @override
  void dispose() {
    sl<PerfilRepository>()
        .estudianteActivoEpoch
        .removeListener(_onEstudianteActivoCambio);
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
    // Recarga vía listener de estudianteActivoEpoch (evita doble fetch).
  }

  Future<void> _cargarFlagCitacion() async {
    try {
      final resp = await sl<ApiClient>().dio.get<Map<String, dynamic>>(
        '/feature-flags',
      );
      if (mounted) {
        setState(() => _citacionActiva = resp.data?['citacion'] == true);
      }
    } on Object {
      if (mounted) setState(() => _citacionActiva = false);
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
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
      // Chip al instante; listado después.
      if (mounted) {
        setState(() {
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
      final items = await sl<IncidenciasApi>().listar(id);
      setState(() {
        _items = items;
        _estudianteId = id;
        _hijo = hijo;
        _cargando = false;
      });
    } on DioException catch (e) {
      setState(() {
        _error = ApiError.deDio(e).mensaje;
        _cargando = false;
      });
    } on ApiError catch (e) {
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      setState(() {
        _error = 'No se pudieron cargar las incidencias. Inténtalo de nuevo.';
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
          const FondoAsiscole(estilo: FondoEstilo.incidencias),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Incidencias',
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
                if (!_citacionActiva)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _ChipCitacionDeshabilitada(),
                  ),
                Expanded(
                  child: _cargando
                      ? const PantallaCargaAsiscole(
                          mensaje: 'Cargando incidencias…',
                        )
                      : _error != null
                          ? Center(
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
                            )
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: _items!.isEmpty
                                  ? ListView(
                                      children: const [
                                        SizedBox(height: 80),
                                        EmptyStateAsiscole(
                                          mensaje:
                                              'No hay incidencias registradas',
                                        ),
                                      ],
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        24,
                                      ),
                                      itemCount: _items!.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (_, i) {
                                        final it = _items![i];
                                        return _CardIncidencia(
                                          item: it,
                                          onTap: () => _detalle(it),
                                        );
                                      },
                                    ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _detalle(IncidenciaResumen it) async {
    await mostrarSheetSeccion(
      builder: (ctx) => _DetalleIncidenciaSheet(
        item: it,
        estudianteId: _estudianteId,
        onConfirmada: (actualizado) {
          setState(() {
            _items = [
              for (final x in _items!)
                if (x.id == actualizado.id) actualizado else x,
            ];
          });
        },
      ),
    );
  }
}

class _ChipCitacionDeshabilitada extends StatelessWidget {
  const _ChipCitacionDeshabilitada();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.borde.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borde),
      ),
      child: const Row(
        children: [
          Icon(Icons.event_busy, size: 18, color: AppTheme.textoSecundario),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Citaciones — próximamente (deshabilitado)',
              style: TextStyle(
                color: AppTheme.textoSecundario,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetalleIncidenciaSheet extends StatefulWidget {
  const _DetalleIncidenciaSheet({
    required this.item,
    required this.estudianteId,
    required this.onConfirmada,
  });

  final IncidenciaResumen item;
  final int? estudianteId;
  final ValueChanged<IncidenciaResumen> onConfirmada;

  @override
  State<_DetalleIncidenciaSheet> createState() =>
      _DetalleIncidenciaSheetState();
}

class _DetalleIncidenciaSheetState extends State<_DetalleIncidenciaSheet> {
  late IncidenciaResumen _item = widget.item;
  bool _enviando = false;
  String? _error;

  Future<void> _confirmar() async {
    final estId = widget.estudianteId;
    if (estId == null || _item.confirmada) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await sl<IncidenciasApi>().confirmar(
        incidenciaId: _item.id,
        estudianteId: estId,
      );
      final actualizado = _item.copyWith(
        confirmada: true,
        confirmadaEn: DateTime.now().toIso8601String(),
      );
      setState(() {
        _item = actualizado;
        _enviando = false;
      });
      widget.onConfirmada(actualizado);
    } on ApiError catch (e) {
      setState(() {
        // 404 genérico del canal / ruta inexistente en un servidor viejo se
        // mapea a STUDENT_LINK_NOT_FOUND; no implica datos de login incorrectos.
        _error = e.codigo == CodigosError.vinculoNoEncontrado
            ? 'No se pudo confirmar esta incidencia. '
                'Si el listado carga bien, el servidor del canal puede estar '
                'desactualizado; inténtalo más tarde.'
            : e.mensaje;
        _enviando = false;
      });
    } on DioException catch (e) {
      final api = ApiError.deDio(e);
      setState(() {
        _error = api.codigo == CodigosError.vinculoNoEncontrado
            ? 'No se pudo confirmar esta incidencia. '
                'Si el listado carga bien, el servidor del canal puede estar '
                'desactualizado; inténtalo más tarde.'
            : api.mensaje;
        _enviando = false;
      });
    } catch (_) {
      setState(() {
        _error = 'No se pudo confirmar. Inténtalo de nuevo.';
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borde,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _item.falta,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppTheme.texto,
                    ),
                  ),
                ),
                if (_item.esGrave)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.moradoClaro.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Grave',
                      style: TextStyle(
                        color: AppTheme.moradoPrincipal,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.check_circle, color: AppTheme.celeste),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Categoría: ${_item.categoria}',
              style: const TextStyle(color: AppTheme.textoSecundario),
            ),
            const SizedBox(height: 6),
            Text(
              'Reportado por: ${_item.reportadoPor}',
              style: const TextStyle(color: AppTheme.textoSecundario),
            ),
            const SizedBox(height: 6),
            Text(
              'Fecha: ${_item.fecha}',
              style: const TextStyle(color: AppTheme.textoSecundario),
            ),
            const SizedBox(height: 16),
            if (_item.confirmada)
              const Row(
                children: [
                  Icon(Icons.verified, color: AppTheme.celeste),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ya confirmaste que recibiste esta incidencia',
                      style: TextStyle(
                        color: AppTheme.texto,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _enviando ? null : _confirmar,
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.mark_email_read_outlined),
                  label: const Text('Confirmar que recibí esta incidencia'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFF991B1B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardIncidencia extends StatelessWidget {
  const _CardIncidencia({required this.item, required this.onTap});

  final IncidenciaResumen item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    DateTime? fecha;
    try {
      fecha = DateTime.parse(item.fecha);
    } catch (_) {}
    final mes = fecha != null
        ? DateFormat('MMM', 'es_PE').format(fecha).toUpperCase()
        : '—';
    final dia = fecha != null ? '${fecha.day}' : '—';

    return Material(
      color: AppTheme.blanco,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: item.confirmada
                  ? AppTheme.celeste.withValues(alpha: 0.5)
                  : AppTheme.borde,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  children: [
                    Text(
                      mes,
                      style: const TextStyle(
                        color: AppTheme.moradoSecundario,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      dia,
                      style: const TextStyle(
                        color: AppTheme.texto,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: AppTheme.borde,
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.moradoClaro.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.report_outlined,
                  color: AppTheme.moradoPrincipal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.falta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.texto,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.categoria} · ${item.reportadoPor}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textoSecundario,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.confirmada
                          ? 'Confirmada por el apoderado'
                          : 'Pendiente de confirmación',
                      style: TextStyle(
                        color: item.confirmada
                            ? AppTheme.celeste
                            : AppTheme.ambar,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (item.esGrave)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Grave',
                    style: TextStyle(
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                )
              else if (item.confirmada)
                const Icon(Icons.verified, color: AppTheme.celeste, size: 22)
              else
                const Icon(Icons.check_circle_outline,
                    color: AppTheme.textoSecundario, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
