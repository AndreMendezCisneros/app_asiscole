import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/theme/asis_colors.dart';
import '../../../core/widgets/chip_hijo_activo.dart';
import '../../../core/widgets/day_status_badge.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../../core/widgets/selector_hijo_sheet.dart';
import '../../../core/widgets/tour_asiscole.dart';
import '../../auth/domain/perfil.dart';
import '../../perfil/data/perfil_repository.dart';
import '../data/asistencias_api.dart';

/// El mes en curso cambia durante el día; los ya cerrados, casi nunca.
const _ttlMesEnCurso = Duration(seconds: 45);

class AsistenciasPage extends StatefulWidget {
  const AsistenciasPage({super.key});

  @override
  State<AsistenciasPage> createState() => _AsistenciasPageState();
}

class _AsistenciasPageState extends State<AsistenciasPage> {
  List<DiaAsistencia>? _dias;
  Map<String, DiaAsistencia> _porFecha = const {};
  String? _error;
  bool _cargando = true;
  late DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _seleccionado;
  EstudianteVinculado? _hijo;
  int? _estudianteId;
  int _epochVisto = 0;

  /// Meses ya descargados en esta visita, por `estudiante-año-mes`.
  ///
  /// Solo en memoria: la asistencia no se guarda en el dispositivo (Ley N.º
  /// 29733, minimización), así que desaparece al salir de la pantalla y al
  /// cerrar sesión. Evita repetir la petición al ir y volver entre meses.
  final Map<String, _MesCacheado> _mesesEnMemoria = {};

  static final _fmtMes = DateFormat('MMMM yyyy', 'es_PE');
  static final _fmtDiaLargo = DateFormat("EEEE d 'de' MMMM", 'es_PE');

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _seleccionado = DateTime(hoy.year, hoy.month, hoy.day);
    final repo = sl<PerfilRepository>();
    _epochVisto = repo.estudianteActivoEpoch.value;
    repo.estudianteActivoEpoch.addListener(_onEstudianteActivoCambio);
    _cargar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TourAsiscole.mostrarSiCorresponde(
        context,
        seccion: 'asistencias',
        titulo: GuiasTour.asistencias.titulo,
        cuerpo: GuiasTour.asistencias.cuerpo,
      );
    });
  }

  @override
  void dispose() {
    sl<PerfilRepository>()
        .estudianteActivoEpoch
        .removeListener(_onEstudianteActivoCambio);
    super.dispose();
  }

  void _onEstudianteActivoCambio() {
    final epoch = sl<PerfilRepository>().estudianteActivoEpoch.value;
    if (epoch == _epochVisto) return;
    _epochVisto = epoch;
    if (!mounted) return;
    // Otro hijo: lo ya pintado no le pertenece.
    setState(() {
      _dias = null;
      _porFecha = const {};
    });
    unawaited(_cargar(forzar: true));
  }

  Future<void> _cambiarHijoDesdeChip() async {
    await mostrarSelectorHijo(
      context: context,
      estudianteActivoId: _estudianteId,
    );
    // Recarga vía listener de estudianteActivoEpoch (evita doble fetch).
  }

  /// Resuelve el hijo activo y trae su mes.
  ///
  /// [forzar] solo se pide cuando hay motivo (cambio de hijo o pull-to-refresh):
  /// antes se releía perfil y lista de hijos en cada entrada a la pestaña, tres
  /// viajes encadenados al servidor para pintar lo mismo.
  Future<void> _cargar({bool forzar = false}) async {
    final repo = sl<PerfilRepository>();

    // Si ya se sabe de quién son los datos, el mes viaja a la vez que el perfil.
    final idConocido = forzar ? null : repo.estudianteActivoIdCacheado;
    final mesEnVuelo =
        idConocido == null ? null : _pedirMes(idConocido, _mes, forzar: forzar);

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
      // Actualiza el chip de inmediato; el mes sigue cargando.
      if (mounted) {
        setState(() {
          _hijo = hijo;
          _estudianteId = id;
        });
      }
      if (id == null) {
        mesEnVuelo?.ignore();
        setState(() {
          _error = 'Selecciona un estudiante en Perfil.';
          _cargando = false;
        });
        return;
      }
      final List<DiaAsistencia> dias;
      if (mesEnVuelo != null && id == idConocido) {
        dias = await mesEnVuelo;
      } else {
        mesEnVuelo?.ignore();
        dias = await _pedirMes(id, _mes, forzar: forzar);
      }
      _aplicarMes(dias, hijo: hijo, estudianteId: id);
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
        _error = 'No se pudieron cargar las asistencias. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  Future<List<DiaAsistencia>> _pedirMes(
    int estudianteId,
    DateTime mes, {
    bool forzar = false,
  }) async {
    final clave = '$estudianteId-${mes.year}-${mes.month}';
    final guardado = _mesesEnMemoria[clave];
    if (!forzar && guardado != null && guardado.vigente) {
      return guardado.dias;
    }
    final dias = await sl<AsistenciasApi>().mes(
      estudianteId: estudianteId,
      anio: mes.year,
      mes: mes.month,
    );
    _mesesEnMemoria[clave] = _MesCacheado(dias, esMesEnCurso(mes));
    return dias;
  }

  static bool esMesEnCurso(DateTime mes) {
    final hoy = DateTime.now();
    return mes.year == hoy.year && mes.month == hoy.month;
  }

  void _aplicarMes(
    List<DiaAsistencia> dias, {
    required EstudianteVinculado? hijo,
    required int estudianteId,
  }) {
    if (!mounted) return;
    setState(() {
      _dias = dias;
      _hijo = hijo ?? _hijo;
      _estudianteId = estudianteId;
      _porFecha = {
        for (final d in dias) d.fecha: d,
      };
      _cargando = false;
      if (_seleccionado == null ||
          _seleccionado!.year != _mes.year ||
          _seleccionado!.month != _mes.month) {
        final hoy = DateTime.now();
        if (hoy.year == _mes.year && hoy.month == _mes.month) {
          _seleccionado = DateTime(hoy.year, hoy.month, hoy.day);
        } else {
          _seleccionado = DateTime(_mes.year, _mes.month, 1);
        }
      }
    });
  }

  /// Trae otro mes del mismo hijo, sin repetir perfil ni lista de hijos.
  Future<void> _cargarSoloMes(int estudianteId) async {
    setState(() {
      _cargando = true;
      _error = null;
      _dias = null;
      _porFecha = const {};
    });
    try {
      final dias = await _pedirMes(estudianteId, _mes);
      _aplicarMes(dias, hijo: _hijo, estudianteId: estudianteId);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiError.deDio(e).mensaje;
        _cargando = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las asistencias. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  bool get _hayRegistrosReales =>
      _dias?.any((d) =>
          d.horaEntrada != null ||
          d.horaSalida != null ||
          d.estado == 'falta' ||
          d.estado == 'a_tiempo' ||
          d.estado == 'tarde') ??
      false;

  int get _countATiempo =>
      _dias?.where((d) => d.estado == 'a_tiempo').length ?? 0;
  int get _countTarde => _dias?.where((d) => d.estado == 'tarde').length ?? 0;
  int get _countFalta => _dias?.where((d) => d.estado == 'falta').length ?? 0;

  DiaAsistencia? get _diaSeleccionado {
    final s = _seleccionado;
    if (s == null) return null;
    final key =
        '${s.year.toString().padLeft(4, '0')}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
    return _porFecha[key];
  }

  void _cambiarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
    final id = _estudianteId;
    // Cambiar de mes no cambia de hijo: solo hace falta el mes nuevo.
    unawaited(id == null ? _cargar() : _cargarSoloMes(id));
  }

  @override
  Widget build(BuildContext context) {
    final mesLabel = _fmtMes.format(_mes);

    return Scaffold(
      backgroundColor: context.asis.fondo,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.asistencias),
          SafeArea(
            child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Asistencias',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: context.asis.texto,
                              ),
                    ),
                  ),
                ],
              ),
            ),
            if (_hijo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChipHijoActivo(
                    nombre: _hijo!.nombre,
                    detalle: '${_hijo!.grado} ${_hijo!.seccion}'.trim(),
                    onCambiar: () => unawaited(_cambiarHijoDesdeChip()),
                  ),
                ),
              ),
            if (_hayRegistrosReales && !_cargando && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _ResumenMes(
                  aTiempo: _countATiempo,
                  tarde: _countTarde,
                  falta: _countFalta,
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _LeyendaAsistencia(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: context.asis.superficie,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: context.asis.borde),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _cambiarMes(-1),
                      icon: const Icon(Icons.chevron_left),
                      color: context.asis.morado,
                    ),
                    Expanded(
                      child: Text(
                        mesLabel[0].toUpperCase() + mesLabel.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.asis.texto,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _cambiarMes(1),
                      icon: const Icon(Icons.chevron_right),
                      color: context.asis.morado,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => unawaited(_cargar(forzar: true)),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _cargar(forzar: true),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          // La rejilla se queda en pantalla mientras llegan los
                          // datos: sustituirla por un spinner hacía que cada
                          // cambio de mes pareciera una recarga entera.
                          _CalendarioMes(
                            mes: _mes,
                            porFecha: _porFecha,
                            seleccionado: _seleccionado,
                            onSeleccionar: (d) =>
                                setState(() => _seleccionado = d),
                          ),
                          const SizedBox(height: 16),
                          if (_cargando)
                            const _PanelCargando()
                          else if (!_hayRegistrosReales)
                            const EmptyStateAsiscole(
                              mensaje:
                                  'Todavía no hay llegadas ni salidas este mes. '
                                  'Cuando el colegio registre una entrada o '
                                  'salida, el día se marcará en el calendario '
                                  'y verás el detalle aquí abajo.',
                              mostrarLogo: false,
                            )
                          else
                            _PanelDia(
                              dia: _diaSeleccionado,
                              fecha: _seleccionado,
                            ),
                        ],
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
}

class _MesCacheado {
  _MesCacheado(this.dias, this.enCurso) : _guardadoEn = DateTime.now();

  final List<DiaAsistencia> dias;
  final bool enCurso;
  final DateTime _guardadoEn;

  bool get vigente =>
      !enCurso || DateTime.now().difference(_guardadoEn) < _ttlMesEnCurso;
}

/// Hueco del panel del día mientras llegan los datos del mes.
class _PanelCargando extends StatelessWidget {
  const _PanelCargando();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.asis.superficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.asis.borde),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BarraFantasma(ancho: 150),
          SizedBox(height: 14),
          _BarraFantasma(),
          SizedBox(height: 10),
          _BarraFantasma(ancho: 200),
        ],
      ),
    );
  }
}

class _BarraFantasma extends StatelessWidget {
  const _BarraFantasma({this.ancho});

  final double? ancho;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      height: 12,
      decoration: BoxDecoration(
        color: context.asis.borde,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _CalendarioMes extends StatelessWidget {
  const _CalendarioMes({
    required this.mes,
    required this.porFecha,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final DateTime mes;
  final Map<String, DiaAsistencia> porFecha;
  final DateTime? seleccionado;
  final ValueChanged<DateTime> onSeleccionar;

  static const _labels = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];

  @override
  Widget build(BuildContext context) {
    final primerDia = DateTime(mes.year, mes.month, 1);
    // Lunes = 1 … Domingo = 7 en DateTime.weekday
    final offset = primerDia.weekday - 1;
    final diasEnMes = DateTime(mes.year, mes.month + 1, 0).day;
    final celdas = offset + diasEnMes;
    final filas = (celdas / 7).ceil();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.asis.superficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.asis.borde),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final l in _labels)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.asis.textoSecundario,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var f = 0; f < filas; f++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: _celda(context, f * 7 + c, offset, diasEnMes),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _celda(BuildContext context, int index, int offset, int diasEnMes) {
    final diaNum = index - offset + 1;
    if (diaNum < 1 || diaNum > diasEnMes) {
      return const SizedBox(height: 44);
    }
    final fecha = DateTime(mes.year, mes.month, diaNum);
    final key =
        '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
    final registro = porFecha[key];
    final sel = seleccionado != null &&
        seleccionado!.year == fecha.year &&
        seleccionado!.month == fecha.month &&
        seleccionado!.day == fecha.day;

    Color? borde;
    if (registro != null) {
      borde = switch (registro.estado) {
        'a_tiempo' => context.asis.celeste,
        'tarde' => context.asis.ambarIncidencia,
        'falta' => context.asis.morado,
        _ => (registro.horaEntrada != null || registro.horaSalida != null)
            ? context.asis.moradoClaro
            : null,
      };
    }

    return GestureDetector(
      onTap: () => onSeleccionar(fecha),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: sel ? 40 : 36,
              height: sel ? 40 : 36,
              decoration: BoxDecoration(
                color: sel ? context.asis.morado : Colors.transparent,
                shape: BoxShape.circle,
                border: sel
                    ? Border.all(color: context.asis.celeste, width: 3)
                    : (borde != null
                        ? Border.all(color: borde, width: 2)
                        : null),
              ),
              alignment: Alignment.center,
              child: Text(
                '$diaNum',
                style: TextStyle(
                  color: sel ? context.asis.sobreMorado : context.asis.texto,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: sel ? 15 : 14,
                ),
              ),
            ),
            if (registro != null && !sel)
              Positioned(
                bottom: 2,
                child: DayStatusBadge(estado: registro.estado, compacto: true),
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelDia extends StatelessWidget {
  const _PanelDia({required this.dia, required this.fecha});

  final DiaAsistencia? dia;
  final DateTime? fecha;

  @override
  Widget build(BuildContext context) {
    final labelFecha = fecha == null
        ? 'Día seleccionado'
        : _AsistenciasPageState._fmtDiaLargo.format(fecha!);
    final titulo = labelFecha[0].toUpperCase() + labelFecha.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: context.asis.texto,
          ),
        ),
        const SizedBox(height: 12),
        if (dia == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.asis.superficie,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.asis.borde),
            ),
            child: Text(
              'Sin registro este día',
              style: TextStyle(color: context.asis.textoSecundario),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _MiniCard(
                  titulo: 'Entrada',
                  valor: dia!.horaEntrada ?? '—',
                  icono: Icons.login_rounded,
                  acento: context.asis.celeste,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniCard(
                  titulo: 'Salida',
                  valor: dia!.horaSalida ?? '—',
                  icono: Icons.logout_rounded,
                  acento: context.asis.moradoSecundario,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.asis.superficie,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.asis.borde),
            ),
            child: Row(
              children: [
                Text(
                  'Estado',
                  style: TextStyle(
                    color: context.asis.textoSecundario,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                DayStatusBadge(estado: dia!.estado),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.acento,
  });

  final String titulo;
  final String valor;
  final IconData icono;
  final Color acento;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.asis.superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.asis.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: acento, size: 22),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: TextStyle(
              color: context.asis.textoSecundario,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              color: context.asis.texto,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeyendaAsistencia extends StatelessWidget {
  const _LeyendaAsistencia();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              t,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.asis.textoSecundario,
              ),
            ),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        item(context.asis.celeste, 'A tiempo'),
        item(context.asis.ambarIncidencia, 'Tarde'),
        item(context.asis.morado, 'Falta'),
      ],
    );
  }
}

class _ResumenMes extends StatelessWidget {
  const _ResumenMes({
    required this.aTiempo,
    required this.tarde,
    required this.falta,
  });

  final int aTiempo;
  final int tarde;
  final int falta;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int n, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: context.asis.superficie,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.asis.borde),
            ),
            child: Column(
              children: [
                Text(
                  '$n',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.asis.textoSecundario,
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        cell('A tiempo', aTiempo, context.asis.celeste),
        const SizedBox(width: 8),
        cell('Tarde', tarde, context.asis.ambarIncidencia),
        const SizedBox(width: 8),
        cell('Faltas', falta, context.asis.morado),
      ],
    );
  }
}
