import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/di/injector.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_asiscole.dart';
import '../../../core/widgets/fondo_asiscole.dart';

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
      backgroundColor: AppTheme.fondo,
      body: Stack(
        children: [
          const FondoAsiscole(estilo: FondoEstilo.notas),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Notas',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.texto,
                        ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _cargando
                        ? const CircularProgressIndicator()
                        : _activo
                            ? const EmptyStateAsiscole(
                                mensaje:
                                    'El módulo de notas estará disponible aquí.',
                              )
                            : const EmptyStateAsiscole(
                                mensaje:
                                    'Próximamente\nLas notas se activarán sin una nueva versión.',
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
