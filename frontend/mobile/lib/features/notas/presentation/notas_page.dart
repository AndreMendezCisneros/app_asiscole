import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/network/api_client.dart';

/// Pantalla de Notas (RF-H): visible, desactivada por feature flag remoto.
class NotasPage extends StatefulWidget {
  const NotasPage({super.key});

  @override
  State<NotasPage> createState() => _NotasPageState();
}

class _NotasPageState extends State<NotasPage> {
  bool _cargando = true;
  bool _activo = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resp = await sl<ApiClient>().dio.get<Map<String, dynamic>>(
        '/feature-flags',
      );
      setState(() {
        _activo = resp.data?['notas'] == true;
        _cargando = false;
      });
    } on DioException {
      setState(() {
        _activo = false;
        _cargando = false;
      });
    } catch (_) {
      setState(() {
        _activo = false;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notas')),
      body: Center(
        child: _cargando
            ? const CircularProgressIndicator()
            : _activo
                ? const Text('El módulo de notas estará disponible aquí.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Próximamente',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text('Las notas se activarán sin una nueva versión.'),
                    ],
                  ),
      ),
    );
  }
}
