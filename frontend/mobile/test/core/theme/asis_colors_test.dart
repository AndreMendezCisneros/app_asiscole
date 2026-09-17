import 'dart:math' as math;

import 'package:asiscole_app/core/theme/app_theme.dart';
import 'package:asiscole_app/core/theme/asis_colors.dart';
import 'package:asiscole_app/core/theme/preferencia_tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _luminancia(Color c) {
  double lineal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lineal(c.r) + 0.7152 * lineal(c.g) + 0.0722 * lineal(c.b);
}

/// Relación de contraste WCAG entre dos colores opacos.
double _contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  final mayor = math.max(la, lb);
  final menor = math.min(la, lb);
  return (mayor + 0.05) / (menor + 0.05);
}

void main() {
  test('la paleta clara repite los valores que ya usaba la app', () {
    const claro = AsisColors.claro;
    expect(claro.fondo, AppTheme.fondo);
    expect(claro.superficie, AppTheme.blanco);
    expect(claro.superficieAlta, AppTheme.blanco);
    expect(claro.texto, AppTheme.texto);
    expect(claro.textoSecundario, AppTheme.textoSecundario);
    expect(claro.borde, AppTheme.borde);
    expect(claro.morado, AppTheme.moradoPrincipal);
    expect(claro.moradoSecundario, AppTheme.moradoSecundario);
    expect(claro.moradoClaro, AppTheme.moradoClaro);
    expect(claro.celeste, AppTheme.celeste);
    expect(claro.verdeEntrada, AppTheme.verdeEntrada);
    expect(claro.indigoSalida, AppTheme.indigoSalida);
    expect(claro.ambarIncidencia, AppTheme.ambarIncidencia);
  });

  test('los dos temas exponen su paleta como extensión', () {
    expect(AppTheme.claro.extension<AsisColors>(), AsisColors.claro);
    expect(AppTheme.oscuro.extension<AsisColors>(), AsisColors.oscuro);
  });

  test('el texto sobre el fondo oscuro cumple WCAG AA', () {
    const oscuro = AsisColors.oscuro;
    expect(_contraste(oscuro.texto, oscuro.fondo), greaterThan(4.5));
    expect(_contraste(oscuro.texto, oscuro.superficie), greaterThan(4.5));
    expect(_contraste(oscuro.textoSecundario, oscuro.fondo), greaterThan(4.5));
    expect(
      _contraste(oscuro.textoSecundario, oscuro.superficie),
      greaterThan(4.5),
    );
    // Lo que va escrito encima del morado se invierte en oscuro.
    expect(_contraste(oscuro.sobreMorado, oscuro.morado), greaterThan(4.5));
    expect(_contraste(oscuro.avisoTexto, oscuro.avisoFondo), greaterThan(4.5));
  });

  test('el tema por defecto es el del sistema', () async {
    SharedPreferences.setMockInitialValues({});
    final preferencia = PreferenciaTema();
    await preferencia.cargar();
    expect(preferencia.modo.value, ThemeMode.system);
  });

  test('la elección sobrevive al arranque', () async {
    SharedPreferences.setMockInitialValues({});
    await PreferenciaTema().cambiar(ThemeMode.dark);

    final otra = PreferenciaTema();
    await otra.cargar();
    expect(otra.modo.value, ThemeMode.dark);
  });

  test('un valor desconocido en disco cae en automático', () async {
    SharedPreferences.setMockInitialValues({'tema_modo': 'sepia'});
    final preferencia = PreferenciaTema();
    await preferencia.cargar();
    expect(preferencia.modo.value, ThemeMode.system);
  });
}
