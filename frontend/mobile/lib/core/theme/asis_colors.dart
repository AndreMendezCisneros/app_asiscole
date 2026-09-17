import 'package:flutter/material.dart';

/// Colores de marca que dependen del brillo, accesibles con `context.asis`.
///
/// La paleta clara repite **exactamente** los valores que la app ya usaba: el
/// modo claro no cambia ni un píxel al migrar una pantalla a estos tokens.
/// La oscura es azul noche, y los colores de marca llevan variante aclarada
/// porque el morado `#5B21E6` sobre negro no llega al contraste AA.
@immutable
class AsisColors extends ThemeExtension<AsisColors> {
  const AsisColors({
    required this.fondo,
    required this.superficie,
    required this.superficieAlta,
    required this.borde,
    required this.texto,
    required this.textoSecundario,
    required this.morado,
    required this.sobreMorado,
    required this.moradoSecundario,
    required this.moradoClaro,
    required this.celeste,
    required this.verdeEntrada,
    required this.indigoSalida,
    required this.ambarIncidencia,
    required this.avisoFondo,
    required this.avisoTexto,
    required this.sombraNav,
  });

  /// Fondo de las pantallas.
  final Color fondo;

  /// Tarjetas, listas y hojas.
  final Color superficie;

  /// Campos de texto y chips, un escalón por encima de [superficie].
  final Color superficieAlta;

  final Color borde;
  final Color texto;
  final Color textoSecundario;
  final Color morado;

  /// Texto e iconos encima de [morado]. En oscuro el morado se aclara, así que
  /// el blanco deja de tener contraste y se invierte a casi negro.
  final Color sobreMorado;

  final Color moradoSecundario;
  final Color moradoClaro;
  final Color celeste;
  final Color verdeEntrada;
  final Color indigoSalida;
  final Color ambarIncidencia;

  /// Franja de «sin conexión».
  final Color avisoFondo;
  final Color avisoTexto;

  /// Sombra de la barra de navegación flotante.
  final Color sombraNav;

  /// Valores vigentes de la app en modo claro. No se tocan.
  static const AsisColors claro = AsisColors(
    fondo: Color(0xFFF8FAFC),
    superficie: Color(0xFFFFFFFF),
    superficieAlta: Color(0xFFFFFFFF),
    borde: Color(0xFFE2E8F0),
    texto: Color(0xFF0F172A),
    textoSecundario: Color(0xFF475569),
    morado: Color(0xFF5B21E6),
    sobreMorado: Color(0xFFFFFFFF),
    moradoSecundario: Color(0xFF7C3AED),
    moradoClaro: Color(0xFFA855F7),
    celeste: Color(0xFF22C7F2),
    verdeEntrada: Color(0xFF059669),
    indigoSalida: Color(0xFF4338CA),
    ambarIncidencia: Color(0xFFD97706),
    avisoFondo: Color(0xFFFFF3CD),
    avisoTexto: Color(0xFF856404),
    sombraNav: Color(0x140F172A),
  );

  /// Azul noche. Texto principal sobre 14:1 y secundario sobre 7:1.
  static const AsisColors oscuro = AsisColors(
    fondo: Color(0xFF0B1020),
    superficie: Color(0xFF161B2E),
    superficieAlta: Color(0xFF1E2438),
    borde: Color(0xFF2A3150),
    texto: Color(0xFFE8EAF6),
    textoSecundario: Color(0xFFA0A7C0),
    morado: Color(0xFF8B6BFF),
    sobreMorado: Color(0xFF12081F),
    moradoSecundario: Color(0xFFA78BFA),
    moradoClaro: Color(0xFFC4B5FD),
    celeste: Color(0xFF4FD8FF),
    verdeEntrada: Color(0xFF34D399),
    indigoSalida: Color(0xFF818CF8),
    ambarIncidencia: Color(0xFFFBBF24),
    avisoFondo: Color(0xFF3A2E12),
    avisoTexto: Color(0xFFFBBF24),
    sombraNav: Color(0x66000000),
  );

  @override
  AsisColors copyWith({
    Color? fondo,
    Color? superficie,
    Color? superficieAlta,
    Color? borde,
    Color? texto,
    Color? textoSecundario,
    Color? morado,
    Color? sobreMorado,
    Color? moradoSecundario,
    Color? moradoClaro,
    Color? celeste,
    Color? verdeEntrada,
    Color? indigoSalida,
    Color? ambarIncidencia,
    Color? avisoFondo,
    Color? avisoTexto,
    Color? sombraNav,
  }) {
    return AsisColors(
      fondo: fondo ?? this.fondo,
      superficie: superficie ?? this.superficie,
      superficieAlta: superficieAlta ?? this.superficieAlta,
      borde: borde ?? this.borde,
      texto: texto ?? this.texto,
      textoSecundario: textoSecundario ?? this.textoSecundario,
      morado: morado ?? this.morado,
      sobreMorado: sobreMorado ?? this.sobreMorado,
      moradoSecundario: moradoSecundario ?? this.moradoSecundario,
      moradoClaro: moradoClaro ?? this.moradoClaro,
      celeste: celeste ?? this.celeste,
      verdeEntrada: verdeEntrada ?? this.verdeEntrada,
      indigoSalida: indigoSalida ?? this.indigoSalida,
      ambarIncidencia: ambarIncidencia ?? this.ambarIncidencia,
      avisoFondo: avisoFondo ?? this.avisoFondo,
      avisoTexto: avisoTexto ?? this.avisoTexto,
      sombraNav: sombraNav ?? this.sombraNav,
    );
  }

  @override
  AsisColors lerp(ThemeExtension<AsisColors>? otro, double t) {
    if (otro is! AsisColors) return this;
    return AsisColors(
      fondo: Color.lerp(fondo, otro.fondo, t)!,
      superficie: Color.lerp(superficie, otro.superficie, t)!,
      superficieAlta: Color.lerp(superficieAlta, otro.superficieAlta, t)!,
      borde: Color.lerp(borde, otro.borde, t)!,
      texto: Color.lerp(texto, otro.texto, t)!,
      textoSecundario: Color.lerp(textoSecundario, otro.textoSecundario, t)!,
      morado: Color.lerp(morado, otro.morado, t)!,
      sobreMorado: Color.lerp(sobreMorado, otro.sobreMorado, t)!,
      moradoSecundario:
          Color.lerp(moradoSecundario, otro.moradoSecundario, t)!,
      moradoClaro: Color.lerp(moradoClaro, otro.moradoClaro, t)!,
      celeste: Color.lerp(celeste, otro.celeste, t)!,
      verdeEntrada: Color.lerp(verdeEntrada, otro.verdeEntrada, t)!,
      indigoSalida: Color.lerp(indigoSalida, otro.indigoSalida, t)!,
      ambarIncidencia:
          Color.lerp(ambarIncidencia, otro.ambarIncidencia, t)!,
      avisoFondo: Color.lerp(avisoFondo, otro.avisoFondo, t)!,
      avisoTexto: Color.lerp(avisoTexto, otro.avisoTexto, t)!,
      sombraNav: Color.lerp(sombraNav, otro.sombraNav, t)!,
    );
  }
}

extension AsisColorsContexto on BuildContext {
  /// Paleta del tema vigente. Fuera de un `MaterialApp` cae a la clara.
  AsisColors get asis =>
      Theme.of(this).extension<AsisColors>() ?? AsisColors.claro;
}
