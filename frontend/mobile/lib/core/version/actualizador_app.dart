import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import 'version_app_api.dart';

/// Intenta actualizar. `in_app_update` solo funciona si el APK vino de Play;
/// en sideload abre la ficha o, si tampoco hay tienda, deja que la UI avise
/// que hay que pedir el APK al colegio.
class ActualizadorApp {
  const ActualizadorApp._();

  static Future<ResultadoActualizacion> intentar({
    required PoliticaVersion politica,
    required bool inmediata,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          if (inmediata) {
            await InAppUpdate.performImmediateUpdate();
          } else {
            await InAppUpdate.startFlexibleUpdate();
          }
          return ResultadoActualizacion.iniciada;
        }
      } on Object {
        // Sideload, emulador o Play Services ausente.
      }
    }

    final crudo = (politica.urlTienda ?? '').trim().isNotEmpty
        ? politica.urlTienda!.trim()
        : Env.urlFichaPlay;
    final uri = Uri.tryParse(crudo);
    if (uri != null && await canLaunchUrl(uri)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok
          ? ResultadoActualizacion.tiendaAbierta
          : ResultadoActualizacion.pedirAlColegio;
    }
    return ResultadoActualizacion.pedirAlColegio;
  }
}

enum ResultadoActualizacion { iniciada, tiendaAbierta, pedirAlColegio }
