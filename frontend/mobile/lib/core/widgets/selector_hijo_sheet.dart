import 'package:flutter/material.dart';

import '../di/injector.dart';
import '../theme/asis_colors.dart';
import '../../features/perfil/data/perfil_repository.dart';

/// Bottom sheet para cambiar el estudiante activo sin salir de la sección.
///
/// Se abre de inmediato con los hijos ya conocidos y refresca dentro: antes
/// esperaba a la respuesta del servidor antes de mostrar nada, y con red lenta
/// parecía que el botón no hacía nada.
Future<bool> mostrarSelectorHijo({
  required BuildContext context,
  required int? estudianteActivoId,
}) async {
  final conocidos = sl<PerfilRepository>().estudiantesCacheados;

  // Si ya se sabe que hay un solo hijo, no hay nada que elegir. Cuando no se
  // sabe, se comprueba dentro del sheet en vez de congelar la pantalla.
  if (conocidos != null && conocidos.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solo tienes un estudiante vinculado.')),
    );
    return false;
  }

  final cambiado = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.asis.fondo,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _SelectorHijoSheet(
      estudianteActivoId: estudianteActivoId,
      iniciales: conocidos,
    ),
  );
  return cambiado ?? false;
}

class _SelectorHijoSheet extends StatefulWidget {
  const _SelectorHijoSheet({
    required this.estudianteActivoId,
    required this.iniciales,
  });

  final int? estudianteActivoId;
  final List<EstudianteVinculado>? iniciales;

  @override
  State<_SelectorHijoSheet> createState() => _SelectorHijoSheetState();
}

class _SelectorHijoSheetState extends State<_SelectorHijoSheet> {
  late List<EstudianteVinculado>? _hijos = widget.iniciales;
  late bool _cargando = widget.iniciales == null;
  bool _falloCarga = false;

  /// Hijo cuyo cambio está en curso; bloquea el resto de la lista.
  int? _cambiandoA;

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  Future<void> _refrescar() async {
    try {
      final hijos = await sl<PerfilRepository>().estudiantes(forzar: true);
      if (!mounted) return;
      setState(() {
        _hijos = hijos;
        _cargando = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _falloCarga = _hijos == null;
      });
    }
  }

  Future<void> _elegir(EstudianteVinculado hijo) async {
    if (_cambiandoA != null) return;
    if (hijo.id == widget.estudianteActivoId) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _cambiandoA = hijo.id);
    try {
      await sl<PerfilRepository>().seleccionarEstudiante(hijo.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Object {
      if (!mounted) return;
      setState(() => _cambiandoA = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar de hijo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
              '¿A qué hijo quieres ver?',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: context.asis.texto,
              ),
            ),
            const SizedBox(height: 8),
            ..._contenido(),
          ],
        ),
      ),
    );
  }

  List<Widget> _contenido() {
    final hijos = _hijos;
    if (hijos == null) {
      if (_falloCarga) {
        return [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No se pudieron cargar los hijos.',
              style: TextStyle(color: context.asis.textoSecundario),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _cargando = true;
                _falloCarga = false;
              });
              _refrescar();
            },
            child: const Text('Reintentar'),
          ),
        ];
      }
      return const [_FilaFantasma(), _FilaFantasma()];
    }

    if (hijos.length < 2) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Solo tienes un estudiante vinculado.',
            style: TextStyle(color: context.asis.textoSecundario),
          ),
        ),
      ];
    }

    return [
      for (final h in hijos) _fila(h),
      if (_cargando) const _FilaFantasma(),
    ];
  }

  Widget _fila(EstudianteVinculado hijo) {
    final activo = hijo.id == widget.estudianteActivoId || hijo.activo;
    final cambiando = _cambiandoA == hijo.id;
    final bloqueado = _cambiandoA != null && !cambiando;

    return Opacity(
      opacity: bloqueado ? 0.45 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: !bloqueado,
        leading: cambiando
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Icon(
                activo ? Icons.check_circle : Icons.circle_outlined,
                color: activo ? context.asis.celeste : context.asis.moradoSecundario,
              ),
        title: Text(
          cambiando ? 'Cambiando a ${hijo.nombre}…' : hijo.nombre,
          style: TextStyle(
            fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
            color: context.asis.texto,
          ),
        ),
        subtitle: Text(
          '${hijo.grado} ${hijo.seccion} · ${hijo.colegio}'.trim(),
          style: TextStyle(
            color: context.asis.textoSecundario,
            fontSize: 12,
          ),
        ),
        onTap: () => _elegir(hijo),
      ),
    );
  }
}

/// Fila en gris mientras llega la lista de hijos.
class _FilaFantasma extends StatelessWidget {
  const _FilaFantasma();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: context.asis.borde,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 160,
                  height: 12,
                  decoration: BoxDecoration(
                    color: context.asis.borde,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 110,
                  height: 10,
                  decoration: BoxDecoration(
                    color: context.asis.borde,
                    borderRadius: BorderRadius.circular(5),
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
