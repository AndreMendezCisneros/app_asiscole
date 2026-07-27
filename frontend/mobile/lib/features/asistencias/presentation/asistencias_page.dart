import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/day_status_badge.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../perfil/data/perfil_repository.dart';
import '../data/asistencias_api.dart';

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

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _seleccionado = DateTime(hoy.year, hoy.month, hoy.day);
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

  bool get _hayRegistrosReales =>
      _dias?.any((d) =>
          d.horaEntrada != null ||
          d.horaSalida != null ||
          d.estado == 'falta' ||
          d.estado == 'a_tiempo' ||
          d.estado == 'tarde') ??
      false;

  DiaAsistencia? get _diaSeleccionado {
    final s = _seleccionado;
    if (s == null) return null;
    final key =
        '${s.year.toString().padLeft(4, '0')}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
    return _porFecha[key];
  }

  void _cambiarMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final mesLabel = DateFormat('MMMM yyyy', 'es_PE').format(_mes);

    return Scaffold(
      backgroundColor: AppTheme.fondo,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.asistencias),
          SafeArea(
            child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Asistencias',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.texto,
                              ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.blanco,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.borde),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _cambiarMes(-1),
                      icon: const Icon(Icons.chevron_left),
                      color: AppTheme.moradoPrincipal,
                    ),
                    Expanded(
                      child: Text(
                        mesLabel[0].toUpperCase() + mesLabel.substring(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.texto,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _cambiarMes(1),
                      icon: const Icon(Icons.chevron_right),
                      color: AppTheme.moradoPrincipal,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
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
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            children: [
                              _CalendarioMes(
                                mes: _mes,
                                porFecha: _porFecha,
                                seleccionado: _seleccionado,
                                onSeleccionar: (d) =>
                                    setState(() => _seleccionado = d),
                              ),
                              const SizedBox(height: 16),
                              if (!_hayRegistrosReales)
                                const EmptyStateAsiscole(
                                  mensaje:
                                      'Aún no hay llegadas ni salidas este mes '
                                      'en el colegio. Cuando el SIE registre una '
                                      'entrada, aparecerá aquí.',
                                  mostrarLogo: false,
                                )
                              else
                                _PanelDia(dia: _diaSeleccionado, fecha: _seleccionado),
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
        color: AppTheme.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borde),
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
                    style: const TextStyle(
                      color: AppTheme.textoSecundario,
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
                      child: _celda(f * 7 + c, offset, diasEnMes),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _celda(int index, int offset, int diasEnMes) {
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
        'a_tiempo' => AppTheme.celeste,
        'tarde' => AppTheme.ambar,
        'falta' => AppTheme.moradoPrincipal,
        _ => (registro.horaEntrada != null || registro.horaSalida != null)
            ? AppTheme.moradoClaro
            : null,
      };
    }

    return GestureDetector(
      onTap: () => onSeleccionar(fecha),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: sel ? AppTheme.moradoPrincipal : Colors.transparent,
                shape: BoxShape.circle,
                border: !sel && borde != null
                    ? Border.all(color: borde, width: 2)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$diaNum',
                style: TextStyle(
                  color: sel ? Colors.white : AppTheme.texto,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
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
        : DateFormat("EEEE d 'de' MMMM", 'es_PE').format(fecha!);
    final titulo = labelFecha[0].toUpperCase() + labelFecha.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppTheme.texto,
          ),
        ),
        const SizedBox(height: 12),
        if (dia == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.blanco,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borde),
            ),
            child: const Text(
              'Sin registro este día',
              style: TextStyle(color: AppTheme.textoSecundario),
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
                  acento: AppTheme.celeste,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniCard(
                  titulo: 'Salida',
                  valor: dia!.horaSalida ?? '—',
                  icono: Icons.logout_rounded,
                  acento: AppTheme.moradoSecundario,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.blanco,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borde),
            ),
            child: Row(
              children: [
                const Text(
                  'Estado',
                  style: TextStyle(
                    color: AppTheme.textoSecundario,
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
        color: AppTheme.blanco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: acento, size: 22),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: const TextStyle(
              color: AppTheme.textoSecundario,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              color: AppTheme.texto,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
