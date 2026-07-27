import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injector.dart';
import '../../../core/push/servicio_push.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/filter_chip_row.dart';
import '../../../core/widgets/fondo_asiscole.dart';
import '../../../core/widgets/search_field_asiscole.dart';
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

class _VistaState extends State<_Vista> {
  StreamSubscription<void>? _avisos;
  final _busqueda = TextEditingController();
  String _filtro = 'todos';
  String _consulta = '';
  Timer? _debounceBusqueda;
  late final DateFormat _horaFmt = DateFormat('HH:mm', 'es_PE');
  late final DateFormat _diaFmt = DateFormat('d MMM', 'es_PE');

  @override
  void initState() {
    super.initState();
    _avisos = sl<ServicioPush>().avisosDeMensaje.listen((_) {
      if (mounted) {
        context.read<MensajesCubit>().cargar(silencioso: true);
      }
    });
  }

  @override
  void dispose() {
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

  List<Mensaje> _filtrar(List<Mensaje> items) {
    return items.where((m) {
      if (_filtro == 'no_leidos' && m.leido) return false;
      if (_consulta.isEmpty) return true;
      return m.texto.toLowerCase().contains(_consulta) ||
          m.tipo.toLowerCase().contains(_consulta) ||
          (m.colegio?.toLowerCase().contains(_consulta) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
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
                final ahora = DateTime.now();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        'Mensajes',
                        style:
                            Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.texto,
                                ),
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
                                      final local = m.emitidoEn.toLocal();
                                      final mismaFecha =
                                          local.year == ahora.year &&
                                              local.month == ahora.month &&
                                              local.day == ahora.day;
                                      final marca = mismaFecha
                                          ? _horaFmt.format(local)
                                          : _diaFmt.format(local);

                                      return _FilaMensaje(
                                        key: ValueKey(m.id),
                                        mensaje: m,
                                        marcaTiempo: marca,
                                        onTap: () => _detalle(context, m),
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

  Future<void> _detalle(BuildContext context, Mensaje m) async {
    unawaited(context.read<MensajesCubit>().abrir(m));
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.fondo,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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

/// Hilo de solo lectura: burbuja del colegio, sin input de respuesta.
class _DetalleMensajeSheet extends StatelessWidget {
  const _DetalleMensajeSheet({required this.mensaje});

  final Mensaje mensaje;

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat("d 'de' MMMM, HH:mm", 'es_PE');
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
              formato.format(mensaje.emitidoEn.toLocal()),
              style: const TextStyle(
                color: AppTheme.textoSecundario,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
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
            const SizedBox(height: 16),
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
