import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/di/injector.dart';
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

class _Vista extends StatelessWidget {
  const _Vista();

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('dd/MM/yyyy HH:mm', 'es_PE');
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes')),
      body: BlocBuilder<MensajesCubit, MensajesState>(
        builder: (context, state) {
          if (state is MensajesCargando) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is MensajesError) {
            return Center(child: Text(state.mensaje));
          }
          final listos = state as MensajesListos;
          if (listos.items.isEmpty) {
            return Center(
              child: Text(
                listos.offline
                    ? 'Sin conexión — solo mensajes guardados'
                    : 'Aún no tienes mensajes',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => context.read<MensajesCubit>().cargar(),
            child: ListView.separated(
              itemCount: listos.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = listos.items[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(_icono(m.tipo))),
                  title: Text(
                    m.texto,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: m.leido ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(formato.format(m.emitidoEn.toLocal())),
                  trailing: m.leido
                      ? null
                      : const Icon(Icons.circle, size: 10, color: Colors.teal),
                  onTap: () => _detalle(context, m),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _icono(String tipo) => switch (tipo) {
        'entrada' => 'E',
        'salida' => 'S',
        'incidencia' => 'I',
        'aviso' => 'A',
        _ => 'M',
      };

  Future<void> _detalle(BuildContext context, Mensaje m) async {
    await context.read<MensajesCubit>().abrir(m);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.tipo.toUpperCase(), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Text(m.texto, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
