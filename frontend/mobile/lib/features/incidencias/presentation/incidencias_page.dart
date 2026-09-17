import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/error/error_codes.dart';
import '../../../core/theme/asis_colors.dart';
import '../../../core/widgets/chip_hijo_activo.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/fondo_asiscole.dart';
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
  int _epochVisto = 0;

  /// Último listado por estudiante, solo en memoria (Ley N.º 29733: nada de
  /// incidencias persistidas en el dispositivo). Evita repedir al ir y volver.
  final Map<int, _ListadoCacheado> _listadosEnMemoria = {};

  @override
  String get rutaDeEstaSeccion => '/incidencias';

  @override
  void initState() {
    super.initState();
    final repo = sl<PerfilRepository>();
    _epochVisto = repo.estudianteActivoEpoch.value;
    repo.estudianteActivoEpoch.addListener(_onEstudianteActivoCambio);
    unawaited(_cargar());
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
    // Otro hijo: lo ya pintado no le pertenece.
    setState(() => _items = null);
    unawaited(_cargar(forzar: true));
  }

  Future<void> _cambiarHijoDesdeChip() async {
    await mostrarSelectorHijo(
      context: context,
      estudianteActivoId: _estudianteId,
    );
    // Recarga vía listener de estudianteActivoEpoch (evita doble fetch).
  }

  /// Resuelve el hijo activo y trae su listado.
  ///
  /// [forzar] solo cuando hay motivo (cambio de hijo o pull-to-refresh): releer
  /// perfil y lista de hijos en cada entrada costaba dos viajes antes de poder
  /// pedir siquiera las incidencias.
  Future<void> _cargar({bool forzar = false}) async {
    final repo = sl<PerfilRepository>();

    // Si ya se sabe de quién son los datos, el listado viaja con el perfil.
    final idConocido = forzar ? null : repo.estudianteActivoIdCacheado;
    final listadoEnVuelo =
        idConocido == null ? null : _pedirListado(idConocido, forzar: forzar);

    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
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
      // Chip al instante; listado después.
      if (mounted) {
        setState(() {
          _hijo = hijo;
          _estudianteId = id;
        });
      }
      if (id == null) {
        listadoEnVuelo?.ignore();
        setState(() {
          _error = 'Selecciona un estudiante en Perfil.';
          _cargando = false;
        });
        return;
      }
      final List<IncidenciaResumen> items;
      if (listadoEnVuelo != null && id == idConocido) {
        items = await listadoEnVuelo;
      } else {
        listadoEnVuelo?.ignore();
        items = await _pedirListado(id, forzar: forzar);
      }
      if (!mounted) return;
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

  Future<List<IncidenciaResumen>> _pedirListado(
    int estudianteId, {
    bool forzar = false,
  }) async {
    final guardado = _listadosEnMemoria[estudianteId];
    if (!forzar && guardado != null && guardado.vigente) {
      return guardado.items;
    }
    final items = await sl<IncidenciasApi>().listar(estudianteId);
    _listadosEnMemoria[estudianteId] = _ListadoCacheado(items);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.asis.fondo,
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
                Expanded(
                  child: _cargando
                      ? const _ListadoFantasma()
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
                                      style: TextStyle(
                                        color: context.asis.texto,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: () =>
                                          unawaited(_cargar(forzar: true)),
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () => _cargar(forzar: true),
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
      isScrollControlled: true,
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

class _ListadoCacheado {
  _ListadoCacheado(this.items) : _guardadoEn = DateTime.now();

  static const _ttl = Duration(seconds: 45);

  final List<IncidenciaResumen> items;
  final DateTime _guardadoEn;

  bool get vigente => DateTime.now().difference(_guardadoEn) < _ttl;
}

/// Tarjetas en gris mientras llega el listado: mantiene el sitio de la lista
/// en lugar de vaciar la pantalla con un spinner.
class _ListadoFantasma extends StatelessWidget {
  const _ListadoFantasma();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        height: 96,
        decoration: BoxDecoration(
          color: context.asis.superficie,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.asis.borde),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 170,
              height: 12,
              decoration: BoxDecoration(
                color: context.asis.borde,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: context.asis.borde,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
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
    final altoMaximo = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: altoMaximo),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.asis.borde,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _item.falta,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: context.asis.texto,
                              ),
                            ),
                          ),
                          if (_item.esGrave)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: context.asis.moradoClaro
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Grave',
                                style: TextStyle(
                                  color: context.asis.morado,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          else
                            Icon(
                              Icons.check_circle,
                              color: context.asis.celeste,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Categoría: ${_item.categoria}',
                        style: TextStyle(color: context.asis.textoSecundario),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reportado por: ${_item.reportadoPor}',
                        style: TextStyle(color: context.asis.textoSecundario),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Fecha: ${_item.fecha}',
                        style: TextStyle(color: context.asis.textoSecundario),
                      ),
                      if (_item.observaciones.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _BloqueObservaciones(texto: _item.observaciones),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_item.confirmada)
                Row(
                  children: [
                    Icon(Icons.verified, color: context.asis.celeste),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ya confirmaste que recibiste esta incidencia',
                        style: TextStyle(
                          color: context.asis.texto,
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
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.asis.sobreMorado,
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
      ),
    );
  }
}

/// Observaciones del auxiliar. El scroll lo hace el sheet, no este bloque:
/// un NestedScrollView interno empujaba el botón de confirmar fuera de vista.
class _BloqueObservaciones extends StatelessWidget {
  const _BloqueObservaciones({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.asis.moradoClaro.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.asis.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Observaciones del colegio',
            style: TextStyle(
              color: context.asis.texto,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            texto,
            style: TextStyle(
              color: context.asis.texto,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
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
      color: context.asis.superficie,
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
                  ? context.asis.celeste.withValues(alpha: 0.5)
                  : context.asis.borde,
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
                      style: TextStyle(
                        color: context.asis.moradoSecundario,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      dia,
                      style: TextStyle(
                        color: context.asis.texto,
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
                color: context.asis.borde,
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.asis.moradoClaro.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.report_outlined,
                  color: context.asis.morado,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.asis.texto,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.categoria} · ${item.reportadoPor}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.asis.textoSecundario,
                        fontSize: 13,
                      ),
                    ),
                    if (item.observaciones.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      // Adelanto: el texto completo está en el detalle.
                      Text(
                        item.observaciones,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.asis.textoSecundario,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      item.confirmada
                          ? 'Confirmada por el apoderado'
                          : 'Pendiente de confirmación',
                      style: TextStyle(
                        color: item.confirmada
                            ? context.asis.celeste
                            : context.asis.ambarIncidencia,
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
                Icon(Icons.verified, color: context.asis.celeste, size: 22)
              else
                Icon(Icons.check_circle_outline,
                    color: context.asis.textoSecundario, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
