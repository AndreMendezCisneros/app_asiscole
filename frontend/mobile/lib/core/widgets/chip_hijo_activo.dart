import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/asis_colors.dart';

/// Chip que indica qué hijo se está consultando.
class ChipHijoActivo extends StatelessWidget {
  const ChipHijoActivo({
    super.key,
    required this.nombre,
    this.detalle,
    this.onCambiar,
  });

  final String nombre;
  final String? detalle;
  final VoidCallback? onCambiar;

  @override
  Widget build(BuildContext context) {
    final texto = detalle == null || detalle!.isEmpty
        ? 'Viendo a $nombre'
        : 'Viendo a $nombre · $detalle';
    return Material(
      color: context.asis.superficie,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onCambiar,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.asis.borde),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.face_retouching_natural,
                  size: 18, color: context.asis.morado),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.asis.texto,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (onCambiar != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.swap_horiz,
                    size: 18, color: context.asis.moradoSecundario),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cierra el modal del root navigator si la ruta deja de coincidir con [rutaContiene].
mixin CierraSheetAlCambiarTab<T extends StatefulWidget> on State<T> {
  bool sheetAbierto = false;
  GoRouter? _router;
  String get rutaDeEstaSeccion;

  void registrarListenerRuta() {
    _router = GoRouter.of(context);
    _router!.routerDelegate.addListener(_alCambiarRuta);
  }

  void cancelarListenerRuta() {
    _router?.routerDelegate.removeListener(_alCambiarRuta);
  }

  void _alCambiarRuta() {
    if (!mounted || !sheetAbierto) return;
    final loc = _router?.state.uri.path ?? '';
    if (!loc.contains(rutaDeEstaSeccion)) {
      Navigator.of(context, rootNavigator: true).maybePop();
      sheetAbierto = false;
    }
  }

  Future<void> mostrarSheetSeccion({
    required WidgetBuilder builder,
    Color? backgroundColor,
    bool isScrollControlled = false,
  }) async {
    sheetAbierto = true;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor ?? context.asis.fondo,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: builder,
    );
    sheetAbierto = false;
  }
}
