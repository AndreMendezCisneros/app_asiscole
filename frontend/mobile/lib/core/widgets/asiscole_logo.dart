import 'package:flutter/material.dart';

/// Logo de marca desde assets (decode acotado al tamaño en pantalla).
class AsiscoleLogo extends StatelessWidget {
  const AsiscoleLogo({super.key, this.size = 56});

  final double size;

  static const String assetPath = 'assets/brand/logo_asiscole.png';

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * dpr).round().clamp(48, 512);
    return Image.asset(
      assetPath,
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
