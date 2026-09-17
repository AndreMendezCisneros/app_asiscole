import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injector.dart';
import '../../../core/push/servicio_push.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/asis_colors.dart';
import '../../../core/util/formato.dart';
import '../../../core/widgets/chip_hijo_activo.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/filter_chip_row.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../../core/widgets/pantalla_carga_asiscole.dart';
import '../../../core/widgets/search_field_asiscole.dart';
import '../../../core/widgets/tour_asiscole.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../../auth/presentation/auth_state.dart';
import '../../perfil/data/perfil_repository.dart';
import '../domain/filtros_bandeja.dart';
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

class _VistaState extends State<_Vista>
    with CierraSheetAlCambiarTab, WidgetsBindingObserver {
  StreamSubscription<void>? _avisos;
  final _busqueda = TextEditingController();
  String _filtro = 'todos';
  String _consulta = '';
  String? _filtroColegio;
  int? _filtroHijoId;
  Timer? _debounceBusqueda;
  List<EstudianteVinculado> _hijos = [];

  /// Margen entre sincronizaciones al volver a la app (T-02).
  static const Duration _margenRefrescoAlVolver = Duration(seconds: 45);
  DateTime? _ultimoRefrescoAlVolver;

  @override
  String get rutaDeEstaSeccion => '/mensajes';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Sin FCM el listado no se entera solo; al volver a la app refrescamos.
    // Con margen: alternar con otra app diez veces no debe costar diez
    // sincronizaciones de datos y batería.
    final ultimo = _ultimoRefrescoAlVolver;
    final ahora = DateTime.now();
    if (ultimo != null && ahora.difference(ultimo) < _margenRefrescoAlVolver) {
      return;
    }
    _ultimoRefrescoAlVolver = ahora;
    context.read<MensajesCubit>().cargar(silencioso: true);
  }

  /// True si el shell ya está mostrando su propia barra de «sin conexión».
  bool _bannerDelShellVisible(BuildContext context) =>
      context.select<AuthCubit, bool>(
        (cubit) => cubit.state is OfflineMessagesOnly,
      );

  void _limpiarFiltros() {
    _busqueda.clear();
    _debounceBusqueda?.cancel();
    setState(() {
      _filtro = 'todos';
      _consulta = '';
      _filtroColegio = null;
      _filtroHijoId = null;
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
    WidgetsBinding.instance.removeObserver(this);
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

  bool get _mostrarFiltroHijo => _hijos.length >= 2;

  EstudianteVinculado? get _hijoActivo {
    for (final h in _hijos) {
      if (h.activo) return h;
    }
    return _hijos.isEmpty ? null : _hijos.first;
  }

  String _primerNombre(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    return partes.isEmpty ? nombre : partes.first;
  }

  List<Mensaje> _filtrar(List<Mensaje> items) {
    return items.where((m) {
      if (_filtro == 'no_leidos' && m.leido) return false;
      if (_filtro == 'citaciones' && !esCitacion(m)) return false;
      if (_filtroHijoId != null && m.estudianteId != _filtroHijoId) {
        return false;
      }
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

  List<Mensaje>? _fuenteMemo;
  String? _claveMemo;
  List<_FilaBandeja>? _bandejaMemo;

  /// Filtra y agrupa una sola vez por combinación de filtros.
  ///
  /// `build` se ejecuta también al desplazar o al abrir el teclado; recorrer
  /// cientos de mensajes en cada pasada se notaba al escribir en el buscador.
  List<_FilaBandeja> _bandeja(List<Mensaje> items) {
    final clave = '$_filtro|$_consulta|$_filtroHijoId|$_filtroColegio';
    if (identical(_fuenteMemo, items) &&
        clave == _claveMemo &&
        _bandejaMemo != null) {
      return _bandejaMemo!;
    }
    _fuenteMemo = items;
    _claveMemo = clave;
    return _bandejaMemo = _agruparPorDia(_filtrar(items));
  }

  @override
  Widget build(BuildContext context) {
    final activo = _hijoActivo;
    return Scaffold(
      backgroundColor: context.asis.fondo,
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
                  return const PantallaCargaAsiscole(
                    mensaje: 'Cargando mensajes…',
                  );
                }
                if (state is MensajesError) {
                  return EmptyStateAsiscole(
                    mensaje: state.mensaje,
                    onReintentar: () =>
                        context.read<MensajesCubit>().cargar(),
                  );
                }
                final listos = state as MensajesListos;
                final noLeidos = listos.items.where((m) => !m.leido).length;
                final citaciones = listos.items.where(esCitacion).length;
                if (citaciones == 0 && _filtro == 'citaciones') {
                  // El chip se esconde al quedarse sin citaciones (p. ej. tras
                  // cambiar de hijo); el filtro no puede quedar colgado.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _filtro == 'citaciones') {
                      setState(() => _filtro = 'todos');
                    }
                  });
                }
                final filas = _bandeja(listos.items);

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
                              color: context.asis.texto,
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
                    // El shell ya muestra su barra ámbar cuando la sesión está
                     // en modo offline; se evita el aviso duplicado y solo se
                     // informa cuando el fallo es de la sincronización.
                    if (listos.offline && !_bannerDelShellVisible(context))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.wifi_off,
                              size: 16,
                              color: context.asis.avisoTexto,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Mostrando mensajes guardados (sin conexión)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.asis.avisoTexto,
                                ),
                              ),
                            ),
                          ],
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
                          FilterChipItem(
                            id: 'todos',
                            label: 'Todos',
                            badge: listos.items.length,
                          ),
                          FilterChipItem(
                            id: 'no_leidos',
                            label: 'No leídos',
                            badge: noLeidos,
                          ),
                          // Solo cuando hay alguna, como los filtros de hijo y
                          // colegio: un chip que nunca da resultados estorba.
                          if (citaciones > 0)
                            FilterChipItem(
                              id: 'citaciones',
                              label: 'Citaciones',
                              badge: citaciones,
                            ),
                        ],
                      ),
                    ),
                    if (_mostrarFiltroHijo) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: FilterChipRow(
                          selectedId: _filtroHijoId?.toString() ?? 'todos_hijos',
                          onSelected: (id) => setState(() {
                            _filtroHijoId =
                                id == 'todos_hijos' ? null : int.tryParse(id);
                          }),
                          items: [
                            const FilterChipItem(
                              id: 'todos_hijos',
                              label: 'Todos los hijos',
                            ),
                            ..._hijos.map(
                              (h) => FilterChipItem(
                                id: h.id.toString(),
                                label: _primerNombre(h.nombre),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                          : filas.isEmpty
                              ? EmptyStateAsiscole(
                                  mensaje: _mensajeVacio(),
                                  mostrarLogo: false,
                                  etiquetaReintentar: 'Quitar filtros',
                                  onReintentar: _limpiarFiltros,
                                )
                              : RefreshIndicator(
                                  onRefresh: () => context
                                      .read<MensajesCubit>()
                                      .cargar(silencioso: true),
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      24,
                                    ),
                                    itemCount: filas.length,
                                    cacheExtent: 720,
                                    itemBuilder: (context, i) {
                                      final fila = filas[i];
                                      final titulo = fila.titulo;
                                      if (titulo != null) {
                                        return _SeparadorDia(titulo: titulo);
                                      }
                                      final m = fila.mensaje!;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: RepaintBoundary(
                                          child: _FilaMensaje(
                                            key: ValueKey(m.id),
                                            mensaje: m,
                                            marcaTiempo: fila.marcaTiempo,
                                            onTap: () => _detalle(m),
                                          ),
                                        ),
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

  String _mensajeVacio() {
    if (_consulta.isNotEmpty) {
      return 'Sin resultados para «$_consulta».\n'
          'La búsqueda solo mira los mensajes descargados en este teléfono.';
    }
    return switch (_filtro) {
      'no_leidos' => 'No te queda ningún mensaje sin leer.',
      'citaciones' => 'No hay citaciones para este filtro.',
      _ when _filtroHijoId != null => 'Este hijo no tiene mensajes todavía.',
      _ when _filtroColegio != null =>
        'Este colegio no tiene mensajes todavía.',
      _ => 'No hay mensajes con ese filtro',
    };
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

/// Fila de la bandeja: o un separador de día, o un mensaje.
class _FilaBandeja {
  const _FilaBandeja.dia(this.titulo)
      : mensaje = null,
        marcaTiempo = '';
  const _FilaBandeja.mensaje(this.mensaje, this.marcaTiempo) : titulo = null;

  final String? titulo;
  final Mensaje? mensaje;
  final String marcaTiempo;
}

/// Agrupa por día en la zona del colegio, respetando el orden que ya trae la
/// lista (el más reciente primero).
List<_FilaBandeja> _agruparPorDia(List<Mensaje> items) {
  final hoyLima = FechasLima.enLima(DateTime.now().toUtc());
  final hoy = DateTime(hoyLima.year, hoyLima.month, hoyLima.day);

  final filas = <_FilaBandeja>[];
  DateTime? diaEnCurso;
  for (final m in items) {
    final lima = FechasLima.enLima(m.emitidoEn);
    final dia = DateTime(lima.year, lima.month, lima.day);
    if (diaEnCurso == null || dia != diaEnCurso) {
      diaEnCurso = dia;
      filas.add(_FilaBandeja.dia(tituloDia(dia, hoy)));
    }
    // Dentro de un día el encabezado ya da la fecha: basta con la hora.
    filas.add(_FilaBandeja.mensaje(m, FechasLima.horaAmPm(m.emitidoEn)));
  }
  return filas;
}

class _SeparadorDia extends StatelessWidget {
  const _SeparadorDia({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        titulo,
        style: TextStyle(
          color: context.asis.textoSecundario,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
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
    final (icono, color, etiqueta) =
        _estiloTipo(context, mensaje.tipo, mensaje.metadata);
    final nombreHijo = (mensaje.estudianteNombre ?? '').trim();
    final primerNombre = nombreHijo.isEmpty
        ? ''
        : nombreHijo.split(RegExp(r'\s+')).first;

    return Material(
      color: context.asis.superficie,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Icon(icono, color: color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            etiqueta,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          marcaTiempo,
                          style: TextStyle(
                            color: context.asis.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (primerNombre.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        primerNombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.asis.texto,
                          fontSize: 15,
                          fontWeight: mensaje.leido
                              ? FontWeight.w700
                              : FontWeight.w800,
                        ),
                      ),
                    ],
                    if (mensaje.colegio != null &&
                        mensaje.colegio!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        mensaje.colegio!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.asis.textoSecundario,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      mensaje.texto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.asis.textoSecundario,
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
                              ? context.asis.celeste
                              : context.asis.textoSecundario,
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
                                ? context.asis.celeste
                                : context.asis.textoSecundario,
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
                  decoration: BoxDecoration(
                    color: context.asis.moradoClaro,
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

  static (IconData, Color, String) _estiloTipo(
    BuildContext context,
    String tipo, [
    Map<String, dynamic> meta = const {},
  ]) {
    if (tipo == 'aviso') {
      final contexto = '${meta['contexto'] ?? ''}'.trim().toLowerCase();
      if (contexto == 'cita') {
        return (
          Icons.event_available_outlined,
          context.asis.morado,
          'Citación',
        );
      }
      if (contexto == 'pension') {
        return (Icons.payments_outlined, context.asis.moradoSecundario, 'Pensión');
      }
    }
    return switch (tipo) {
      'entrada' => (Icons.login_rounded, context.asis.verdeEntrada, 'Entrada'),
      'salida' => (Icons.logout_rounded, context.asis.indigoSalida, 'Salida'),
      'incidencia' => (
          Icons.warning_amber_rounded,
          context.asis.ambarIncidencia,
          'Incidencia',
        ),
      'aviso' => (Icons.campaign_outlined, context.asis.moradoSecundario, 'Aviso'),
      _ => (Icons.mail_outline, context.asis.textoSecundario, 'Mensaje'),
    };
  }
}

class _DetalleMensajeSheet extends StatelessWidget {
  const _DetalleMensajeSheet({required this.mensaje});

  final Mensaje mensaje;

  @override
  Widget build(BuildContext context) {
    final meta = mensaje.metadata;
    final grado = [meta['grado'], meta['seccion']]
        .where((v) => v != null && '$v'.trim().isNotEmpty)
        .join(' ');
    // El dato importante es el texto del mensaje; los metadatos van después y
    // agrupados, para que no compitan con él.
    final extras = <String>[
      if (mensaje.estudianteNombre != null)
        [
          mensaje.estudianteNombre,
          if (grado.isNotEmpty) '($grado)',
        ].join(' '),
      if (mensaje.colegio != null) '${mensaje.colegio}',
      if (meta['hora'] != null && meta['contexto'] != 'cita')
        'Hora del evento: ${meta['hora']}',
      if (meta['falta'] != null) 'Falta: ${meta['falta']}',
      if (meta['contexto'] == 'cita') ...[
        if (meta['fecha'] != null) 'Fecha: ${_fechaCita(meta['fecha'])}',
        if (meta['hora'] != null) 'Hora: ${meta['hora']}',
        if (meta['motivo'] != null && '${meta['motivo']}'.trim().isNotEmpty)
          'Motivo: ${meta['motivo']}',
        if (meta['alcance'] != null && '${meta['alcance']}'.trim().isNotEmpty)
          'Alcance: ${_alcanceCita('${meta['alcance']}')}',
      ],
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
                  color: context.asis.borde,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _FilaMensaje._estiloTipo(context, mensaje.tipo, mensaje.metadata)
                  .$3,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.asis.texto,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              FechasLima.fechaHoraAmPm(mensaje.emitidoEn),
              style: TextStyle(
                color: context.asis.textoSecundario,
                fontSize: 13,
              ),
            ),
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
                    color: context.asis.superficie,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(color: context.asis.borde),
                  ),
                  child: Text(
                    mensaje.texto,
                    style: TextStyle(
                      color: context.asis.texto,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...extras.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    e,
                    style: TextStyle(
                      color: context.asis.textoSecundario,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
            // No se muestra el estado de lectura: abrir el detalle ya lo marca
            // como leído, así que decía «pendiente» mientras la lista de detrás
            // decía «leído». Y al apoderado no le aporta nada.
            const SizedBox(height: 12),
            Text(
              'Solo lectura — este canal no permite responder',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.asis.textoSecundario,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fechaCita(Object crudo) {
  final iso = '$crudo';
  if (iso.length < 10) return iso;
  final p = iso.substring(0, 10).split('-');
  if (p.length != 3) return iso;
  return '${p[2]}/${p[1]}/${p[0]}';
}

String _alcanceCita(String crudo) => switch (crudo.trim().toLowerCase()) {
      'individual' => 'Individual',
      'apafa' => 'APAFA',
      'piso' => 'Piso',
      'salon' => 'Salón',
      _ => crudo,
    };

