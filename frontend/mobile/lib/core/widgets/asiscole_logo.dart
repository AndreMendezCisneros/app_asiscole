import 'package:flutter/material.dart';

/// Logo de marca desde assets (decode acotado al tamaño en pantalla).
///
/// El de fondo blanco solo va en el icono de la app y en Perfil. El resto
/// (arranque, carga, login) usa el recorte sin fondo.
class AsiscoleLogo extends StatelessWidget {
  const AsiscoleLogo({super.key, this.size = 56, this.conFondo = false});

  final double size;

  /// `true` en Perfil. El icono de Android se genera aparte desde
  /// `assets/brand/logo_asiscole.png`.
  final bool conFondo;

  static const String assetConFondo = 'assets/brand/logo_asiscole.png';
  static const String assetSinFondo = 'assets/brand/logo_asiscole_sf.png';

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * dpr).round().clamp(48, 512);
    return Image.asset(
      conFondo ? assetConFondo : assetSinFondo,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: px,
      cacheHeight: px,
      gaplessPlayback: true,
    );
  }
}
