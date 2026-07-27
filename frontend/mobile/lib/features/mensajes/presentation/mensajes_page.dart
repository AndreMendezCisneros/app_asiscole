import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injector.dart';
import '../../../core/push/servicio_push.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/formato.dart';
import '../../../core/widgets/chip_hijo_activo.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/filter_chip_row.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../../core/widgets/search_field_asiscole.dart';
import '../../../core/widgets/tour_asiscole.dart';
import '../../perfil/data/perfil_repository.dart';
import '../domain/mensaje.dart';
import 'mensajes_cubit.dart';

class MensajesPage extends StatelessWidget {
  const MensajesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MensajesCubit(sl())..cargar(),
      child: const _Vista(),
    );
  }
}

class _Vista extends StatefulWidget {
  const _Vista();

  @override
  State<_Vista> createState() => _VistaState();
}

class _VistaState extends State<_Vista> with CierraSheetAlCambiarTab {
  StreamSubscription<void>? _avisos;
  final _busqueda = TextEditingController();
  String _filtro = 'todos';
  String _consulta = '';
  String? _filtroColegio;
  Timer? _debounceBusqueda;
  List<EstudianteVinculado> _hijos = [];

  @override
  String get rutaDeEstaSeccion => '/mensajes';

  @override
  void initState() {
    super.initState();
    _avisos = sl<ServicioPush>().avisosDeMensaje.listen((_) {
      if (mounted) {
        context.read<MensajesCubit>().cargar(silencioso: true);
      }
    });
    unawaited(_cargarHijos());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) registrarListenerRuta();
      if (!mounted) return;
      TourAsiscole.mostrarSiCorresponde(
        context,
        seccion: 'mensajes',
        titulo: GuiasTour.mensajes.titulo,
        cuerpo: GuiasTour.mensajes.cuerpo,
      );
    });
  }

  Future<void> _cargarHijos() async {
    try {
      final hijos = await sl<PerfilRepository>().estudiantes();
      if (mounted) setState(() => _hijos = hijos);
    } on Object {
      // Sin hijos no se muestra chip/filtro colegio.
    }
  }

  @override
  void dispose() {
    cancelarListenerRuta();
    _debounceBusqueda?.cancel();
    _avisos?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  void _onBusqueda(String valor) {
    _debounceBusqueda?.cancel();
    _debounceBusqueda = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final limpio = valor.trim().toLowerCase();
      if (limpio == _consulta) return;
      setState(() => _consulta = limpio);
    });
  }

  List<String> get _colegiosDistintos {
    final set = <String>{};
    for (final h in _hijos) {
      if (h.colegio.trim().isNotEmpty) set.add(h.colegio.trim());
    }
    return set.toList()..sort();
  }

  bool get _mostrarFiltroColegio => _colegiosDistintos.length >= 2;

  EstudianteVinculado? get _hijoActivo {
    for (final h in _hijos) {
      if (h.activo) return h;
    }
    return _hijos.isEmpty ? null : _hijos.first;
  }

  List<Mensaje> _filtrar(List<Mensaje> items) {
    return items.where((m) {
      if (_filtro == 'no_leidos' && m.leido) return false;
      if (_filtroColegio != null &&
          (m.colegio ?? '').trim() != _filtroColegio) {
        return false;
      }
      if (_consulta.isEmpty) return true;
      final q = _consulta;
      return m.texto.toLowerCase().contains(q) ||
          m.tipo.toLowerCase().contains(q) ||
          (m.colegio?.toLowerCase().contains(q) ?? false) ||
          (m.estudianteNombre?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final activo = _hijoActivo;
    return Scaffold(
      backgroundColor: AppTheme.fondo,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.mensajes),
          SafeArea(
            child: BlocBuilder<MensajesCubit, MensajesState>(
              buildWhen: (prev, next) =>
                  prev.runtimeType != next.runtimeType ||
                  (prev is MensajesListos &&
                      next is MensajesListos &&
                      (prev.items != next.items ||
                          prev.offline != next.offline)) ||
                  next is MensajesError ||
                  next is MensajesCargando,
              builder: (context, state) {
                if (state is MensajesCargando) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is MensajesError) {
                  return EmptyStateAsiscole(mensaje: state.mensaje);
                }
                final listos = state as MensajesListos;
                final noLeidos = listos.items.where((m) => !m.leido).length;
                final filtrados = _filtrar(listos.items);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        'Mensajes',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.texto,
                            ),
                      ),
                    ),
                    if (activo != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: ChipHijoActivo(
                          nombre: activo.nombre,
                          detalle: '${activo.grado} ${activo.seccion}'.trim(),
                          onCambiar: () => context.go(Rutas.perfil),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SearchFieldAsiscole(
                        controller: _busqueda,
                        hint: 'Buscar mensajes',
                        onChanged: _onBusqueda,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FilterChipRow(
                        selectedId: _filtro,
                        onSelected: (id) => setState(() => _filtro = id),
                        items: [
                          const FilterChipItem(id: 'todos', label: 'Todos'),
                          FilterChipItem(
                            id: 'no_leidos',
                            label: 'No leídos',
                            badge: noLeidos,
                          ),
                        ],
                      ),
                    ),
                    if (_mostrarFiltroColegio) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: FilterChipRow(
                          selectedId: _filtroColegio ?? 'todos_colegios',
                          onSelected: (id) => setState(() {
                            _filtroColegio =
                                id == 'todos_colegios' ? null : id;
                          }),
                          items: [
                            const FilterChipItem(
                              id: 'todos_colegios',
                              label: 'Todos los colegios',
                            ),
                            ..._colegiosDistintos.map(
                              (c) => FilterChipItem(id: c, label: c),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Expanded(
                      child: listos.items.isEmpty
                          ? EmptyStateAsiscole(
                              mensaje: listos.offline
                                  ? 'Sin conexión — solo mensajes guardados'
                                  : 'Aún no tienes mensajes',
                            )
                          : filtrados.isEmpty
                              ? const EmptyStateAsiscole(
                                  mensaje: 'No hay mensajes con ese filtro',
                                  mostrarLogo: false,
                                )
                              : RefreshIndicator(
                                  onRefresh: () => context
                                      .read<MensajesCubit>()
                                      .cargar(silencioso: true),
                                  child: ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      24,
                                    ),
                                    itemCount: filtrados.length,
                                    cacheExtent: 480,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 4),
                                    itemBuilder: (context, i) {
                                      final m = filtrados[i];
                                      final lima = FechasLima.enLima(m.emitidoEn);
                                      final ahoraLima = FechasLima.enLima(
                                        DateTime.now().toUtc(),
                                      );
                                      final mismaFecha =
                                          lima.year == ahoraLima.year &&
                                              lima.month == ahoraLima.month &&
                                              lima.day == ahoraLima.day;
                                      final marca = mismaFecha
                                          ? FechasLima.horaAmPm(m.emitidoEn)
                                          : DateFormat('d MMM', 'es_PE')
                                              .format(
                                                DateTime(
                                                  lima.year,
                                                  lima.month,
                                                  lima.day,
                                                ),
                                              );
                                      return _FilaMensaje(
                                        key: ValueKey(m.id),
                                        mensaje: m,
                                        marcaTiempo: marca,
                                        onTap: () => _detalle(m),
                                      );
                                    },
                                  ),
                                ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _detalle(Mensaje m) async {
    unawaited(context.read<MensajesCubit>().abrir(m));
    if (!mounted) return;
    await mostrarSheetSeccion(
      isScrollControlled: true,
      builder: (_) => _DetalleMensajeSheet(mensaje: m),
    );
  }
}

class _FilaMensaje extends StatelessWidget {
  const _FilaMensaje({
    super.key,
    required this.mensaje,
    required this.marcaTiempo,
    required this.onTap,
  });

  final Mensaje mensaje;
  final String marcaTiempo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (letra, color) = _estiloTipo(mensaje.tipo);
    final subtitulo = [
      if (mensaje.estudianteNombre != null &&
          mensaje.estudianteNombre!.isNotEmpty)
        mensaje.estudianteNombre!,
      if (mensaje.colegio != null && mensaje.colegio!.isNotEmpty)
        mensaje.colegio!,
    ].join(' · ');

    return Material(
      color: AppTheme.blanco,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Text(
                  letra,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tituloTipo(mensaje.tipo),
                            style: TextStyle(
                              fontWeight: mensaje.leido
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              color: AppTheme.texto,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          marcaTiempo,
                          style: const TextStyle(
                            color: AppTheme.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (subtitulo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.moradoSecundario,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      mensaje.texto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textoSecundario,
                        fontWeight:
                            mensaje.leido ? FontWeight.w400 : FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          mensaje.leido
                              ? Icons.done_all
                              : mensaje.entregado
                                  ? Icons.done
                                  : Icons.schedule,
                          size: 14,
                          color: mensaje.leido
                              ? AppTheme.celeste
                              : AppTheme.textoSecundario,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          mensaje.leido
                              ? 'Leído'
                              : mensaje.entregado
                                  ? 'Entregado'
                                  : 'Pendiente',
                          style: TextStyle(
                            fontSize: 11,
                            color: mensaje.leido
                                ? AppTheme.celeste
                                : AppTheme.textoSecundario,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!mensaje.leido) ...[
                const SizedBox(width: 8),
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(
                    color: AppTheme.moradoClaro,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static (String, Color) _estiloTipo(String tipo) => switch (tipo) {
        'entrada' => ('E', AppTheme.celeste),
        'salida' => ('S', AppTheme.moradoSecundario),
        'incidencia' => ('I', AppTheme.moradoPrincipal),
        'aviso' => ('A', AppTheme.moradoClaro),
        _ => ('M', AppTheme.textoSecundario),
      };

  static String _tituloTipo(String tipo) => switch (tipo) {
        'entrada' => 'Entrada',
        'salida' => 'Salida',
        'incidencia' => 'Incidencia',
        'aviso' => 'Aviso',
        _ => 'Mensaje',
      };
}

class _DetalleMensajeSheet extends StatelessWidget {
  const _DetalleMensajeSheet({required this.mensaje});

  final Mensaje mensaje;

  @override
  Widget build(BuildContext context) {
    final meta = mensaje.metadata;
    final extras = <String>[
      if (mensaje.estudianteNombre != null) 'Hijo: ${mensaje.estudianteNombre}',
      if (mensaje.colegio != null) 'Colegio: ${mensaje.colegio}',
      if (meta['grado'] != null) 'Grado: ${meta['grado']}',
      if (meta['seccion'] != null) 'Sección: ${meta['seccion']}',
      if (meta['hora'] != null) 'Hora del evento: ${meta['hora']}',
      if (meta['falta'] != null) 'Falta: ${meta['falta']}',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text(
              _FilaMensaje._tituloTipo(mensaje.tipo),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.texto,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              FechasLima.fechaHoraAmPm(mensaje.emitidoEn),
              style: const TextStyle(
                color: AppTheme.textoSecundario,
                fontSize: 13,
              ),
            ),
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...extras.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    e,
                    style: const TextStyle(
                      color: AppTheme.textoSecundario,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.85,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.blanco,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: AppTheme.borde),
                  ),
                  child: Text(
                    mensaje.texto,
                    style: const TextStyle(
                      color: AppTheme.texto,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              mensaje.leido
                  ? 'Estado: leído'
                  : mensaje.entregado
                      ? 'Estado: entregado'
                      : 'Estado: pendiente de lectura',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textoSecundario,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Solo lectura — este canal no permite responder',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textoSecundario,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
