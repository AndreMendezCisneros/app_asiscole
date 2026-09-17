import 'package:flutter/material.dart';

import 'asis_colors.dart';

/// Tokens y tema de marca Asis Messenger.
///
/// Las constantes siguen siendo los valores del modo claro, para el código que
/// no depende del brillo. Lo que sí cambia entre claro y oscuro se lee del
/// tema con `context.asis` (ver [AsisColors]).
class AppTheme {
  const AppTheme._();

  static const Color moradoPrincipal = Color(0xFF5B21E6);
  static const Color moradoSecundario = Color(0xFF7C3AED);
  static const Color moradoClaro = Color(0xFFA855F7);
  static const Color celeste = Color(0xFF22C7F2);
  static const Color verdeEntrada = Color(0xFF059669);
  static const Color indigoSalida = Color(0xFF4338CA);
  static const Color ambarIncidencia = Color(0xFFD97706);
  static const Color texto = Color(0xFF0F172A);
  static const Color textoSecundario = Color(0xFF475569);
  static const Color fondo = Color(0xFFF8FAFC);
  static const Color borde = Color(0xFFE2E8F0);
  static const Color blanco = Color(0xFFFFFFFF);

  /// Compatibilidad con código antiguo.
  static const Color azulInstitucional = moradoPrincipal;
  static const Color ambar = ambarIncidencia;

  static ThemeData get claro => _claro;
  static ThemeData get oscuro => _oscuro;

  static final ThemeData _claro = _construir(Brightness.light);
  static final ThemeData _oscuro = _construir(Brightness.dark);

  static ThemeData _construir(Brightness brillo) {
    final claro = brillo == Brightness.light;
    final asis = claro ? AsisColors.claro : AsisColors.oscuro;
    final esquema = ColorScheme.fromSeed(
      seedColor: moradoPrincipal,
      brightness: brillo,
      primary: asis.morado,
      secondary: asis.moradoSecundario,
      tertiary: asis.celeste,
      surface: asis.fondo,
      onSurface: asis.texto,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      extensions: <ThemeExtension<dynamic>>[asis],
      scaffoldBackgroundColor: asis.fondo,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: asis.fondo,
        foregroundColor: asis.texto,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: asis.texto,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: asis.superficieAlta,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: asis.borde),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: asis.borde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: asis.morado, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: TextStyle(color: asis.textoSecundario),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: asis.morado,
          foregroundColor: asis.sobreMorado,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: asis.morado,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: asis.borde),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: claro ? asis.borde : asis.superficieAlta,
        selectedColor: asis.moradoClaro.withValues(alpha: 0.35),
        labelStyle: TextStyle(color: asis.texto, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: asis.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: asis.borde),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: asis.borde, thickness: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: asis.texto),
        bodyMedium: TextStyle(color: asis.texto),
        bodySmall: TextStyle(color: asis.textoSecundario),
        titleLarge: TextStyle(
          color: asis.texto,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: asis.texto,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: TextStyle(color: asis.textoSecundario),
      ),
    );
  }
}
