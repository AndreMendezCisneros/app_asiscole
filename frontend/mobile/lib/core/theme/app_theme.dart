import 'package:flutter/material.dart';

/// Tokens y tema de marca Asiscole Messenger.
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
    final esquema = ColorScheme.fromSeed(
      seedColor: moradoPrincipal,
      brightness: brillo,
      primary: moradoPrincipal,
      secondary: moradoSecundario,
      tertiary: celeste,
      surface: claro ? fondo : const Color(0xFF0F172A),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: claro ? fondo : esquema.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: claro ? fondo : esquema.surface,
        foregroundColor: claro ? texto : esquema.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: claro ? texto : esquema.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: claro ? blanco : esquema.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: claro ? borde : esquema.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: claro ? borde : esquema.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: moradoPrincipal, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: const TextStyle(color: textoSecundario),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: moradoPrincipal,
          foregroundColor: blanco,
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
          foregroundColor: moradoPrincipal,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: borde),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: borde,
        selectedColor: moradoClaro.withValues(alpha: 0.35),
        labelStyle: const TextStyle(color: texto, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: blanco,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: borde),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: borde, thickness: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: claro ? texto : esquema.onSurface),
        bodyMedium: TextStyle(color: claro ? texto : esquema.onSurface),
        bodySmall: const TextStyle(color: textoSecundario),
        titleLarge: TextStyle(
          color: claro ? texto : esquema.onSurface,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: claro ? texto : esquema.onSurface,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: const TextStyle(color: textoSecundario),
      ),
    );
  }
}
