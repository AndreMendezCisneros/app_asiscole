import 'dart:io' show Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:equatable/equatable.dart';

/// Datos del equipo que el contrato pide en el login.
class DatosDispositivo extends Equatable {
  const DatosDispositivo({
    required this.deviceId,
    required this.modelo,
    required this.sistemaOperativo,
    required this.plataforma,
  });

  final String deviceId;
  final String modelo;
  final String sistemaOperativo;

  /// `android` o `ios`, tal como los acepta `/perfil/push-token`.
  final String plataforma;

  @override
  List<Object?> get props => [deviceId, modelo, sistemaOperativo, plataforma];
}

/// Lee modelo y sistema operativo del equipo. El `device_id` lo aporta quien
/// llama, porque es un identificador propio y persistente de la instalación.
class InfoDispositivo {
  InfoDispositivo([DeviceInfoPlugin? plugin])
      : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  Future<DatosDispositivo> obtener(String deviceId) async {
    try {
      if (Platform.isAndroid) {
        final info = await _plugin.androidInfo;
        return DatosDispositivo(
          deviceId: deviceId,
          modelo: '${info.manufacturer} ${info.model}',
          sistemaOperativo: 'Android ${info.version.release}',
          plataforma: 'android',
        );
      }
      if (Platform.isIOS) {
        final info = await _plugin.iosInfo;
        return DatosDispositivo(
          deviceId: deviceId,
          modelo: info.utsname.machine,
          sistemaOperativo: '${info.systemName} ${info.systemVersion}',
          plataforma: 'ios',
        );
      }
    } on Object {
      // Si el plugin falla, el login sigue siendo posible sin estos campos.
    }
    return DatosDispositivo(
      deviceId: deviceId,
      modelo: 'Desconocido',
      sistemaOperativo: 'Desconocido',
      plataforma: 'android',
    );
  }

  /// Identificador aleatorio de la instalación, con forma de UUID v4.
  static String generarDeviceId() {
    final azar = Random.secure();
    final bytes = List<int>.generate(16, (_) => azar.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
