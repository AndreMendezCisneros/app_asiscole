import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Engancha Crashlytics sin filtrar datos personales (Ley N.º 29733).
///
/// No se usa `setUserIdentifier` con el teléfono. Las claves custom son
/// `versionCode`, `tenant` y `request_id`: identificadores internos.
class CrashlyticsCanal {
  const CrashlyticsCanal._();

  static Future<void> enganchar() async {
    try {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        !kDebugMode,
      );
      final info = await PackageInfo.fromPlatform();
      await FirebaseCrashlytics.instance.setCustomKey(
        'versionCode',
        info.buildNumber,
      );
    } on Object {
      // Stub de Firebase, tests o emulador sin google-services: la app arranca.
    }
  }

  /// `tenant` es un identificador interno del colegio, no un dato personal.
  static Future<void> registrarTenant(String? tenant) async {
    final valor = (tenant ?? '').trim();
    if (valor.isEmpty) return;
    try {
      await FirebaseCrashlytics.instance.setCustomKey('tenant', valor);
    } on Object {
      // Observabilidad oportunista.
    }
  }

  static Future<void> registrarRequestId(String? requestId) async {
    final valor = (requestId ?? '').trim();
    if (valor.isEmpty) return;
    try {
      await FirebaseCrashlytics.instance.setCustomKey('request_id', valor);
    } on Object {
      // Observabilidad oportunista.
    }
  }
}
