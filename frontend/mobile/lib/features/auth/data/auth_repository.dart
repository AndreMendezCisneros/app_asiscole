import 'package:dio/dio.dart';

import '../../../core/device/info_dispositivo.dart';
import '../../../core/error/api_error.dart';
import '../../../core/error/error_codes.dart';
import '../../../core/legal/terminos_legales.dart';
import '../domain/perfil.dart';
import '../domain/sesion.dart';
import '../domain/solicitud_transferencia.dart';
import 'auth_api.dart';
import 'session_storage.dart';

/// Une la API de autenticación con el almacén cifrado.
///
/// Traduce cualquier fallo de red a [ApiError] para que la UI reaccione al
/// código y nunca al texto.
class AuthRepository {
  AuthRepository({
    required AuthApi api,
    required SessionStorage almacen,
    required InfoDispositivo dispositivo,
    Future<String?> Function()? obtenerPushToken,
    Future<void> Function()? borrarCacheMensajes,
  })  : _api = api,
        _almacen = almacen,
        _dispositivo = dispositivo,
        _obtenerPushToken = obtenerPushToken,
        _borrarCacheMensajes = borrarCacheMensajes;

  final AuthApi _api;
  final SessionStorage _almacen;
  final InfoDispositivo _dispositivo;
  final Future<String?> Function()? _obtenerPushToken;
  final Future<void> Function()? _borrarCacheMensajes;

  Future<Sesion> login({
    required String telefono,
    required String documentoEstudiante,
  }) async {
    return _traducir(() async {
      final datos = await _dispositivo.obtener(await _almacen.deviceId());
      final sesion = await _api.login(
        telefono: telefono,
        documentoEstudiante: documentoEstudiante,
        deviceId: datos.deviceId,
        modelo: datos.modelo,
        sistemaOperativo: datos.sistemaOperativo,
        pushToken: await _pushToken(),
        aceptaTerminos: true,
        terminosVersion: TerminosLegales.version,
      );
      await _almacen.guardarSesion(sesion);
      return sesion;
    });
  }

  Future<SolicitudTransferencia> solicitarTransferencia({
    required String telefono,
    required String documentoEstudiante,
  }) {
    return _traducir(() async {
      return _api.solicitarTransferencia(
        telefono: telefono,
        documentoEstudiante: documentoEstudiante,
        deviceId: await _almacen.deviceId(),
      );
    });
  }

  Future<SolicitudTransferencia> consultarTransferencia(
    String id, {
    required String tokenConsulta,
  }) =>
      _traducir(
        () => _api.consultarTransferencia(id, tokenConsulta: tokenConsulta),
      );

  /// Aprobar cierra la sesión de este dispositivo, así que se limpian los
  /// tokens locales sin esperar a que el backend nos eche.
  Future<void> aprobarTransferencia(String id) => _traducir(() async {
        await _api.aprobarTransferencia(id);
        await _almacen.limpiarTokens();
      });

  Future<void> rechazarTransferencia(String id) =>
      _traducir(() => _api.rechazarTransferencia(id));

  /// Renueva el `session_token` si está en la ventana del día 7 al 10.
  Future<void> renovarSesionSiCorresponde() async {
    if (!await _almacen.tocaRenovarSesion) return;
    try {
      await _almacen.guardarSesion(await _api.renovarSesion());
    } on DioException {
      // Renovar es oportunista: si falla, la sesión vigente sigue sirviendo.
    }
  }

  /// Al arranque: renueva el `data_token` con el `session_token` vigente.
  ///
  /// No borra la sesión si falla por red; sí si el backend indica sesión
  /// expirada o no autenticada.
  Future<void> refrescarDatosAlArranque() async {
    try {
      final emitido = await _api.refrescarDatos();
      await _almacen.guardarDataToken(emitido.dataToken, emitido.dataExpiraEn);
    } on DioException catch (e) {
      final error = ApiError.deDio(e);
      if (error.codigo == CodigosError.sesionExpirada ||
          error.codigo == CodigosError.noAutenticado ||
          error.statusCode == 410 ||
          error.statusCode == 401) {
        await _almacen.limpiarTokens();
        throw error;
      }
      rethrow;
    }
  }

  Future<void> guardarPerfil(Perfil perfil) => _almacen.guardarPerfil(perfil);

  /// Cierra sesión en el backend y borra los tokens y la caché de mensajes.
  ///
  /// La caché guarda el nombre del estudiante y el texto de los avisos, así que
  /// no debe sobrevivir al cierre de sesión: el teléfono puede ser compartido y
  /// la eliminación de cuenta pasa por aquí (Ley N.º 29733, minimización).
  Future<void> cerrarSesion() async {
    try {
      await _api.logout();
    } on DioException {
      // Aunque el backend no responda, la sesión local se cierra igual.
    } finally {
      await _almacen.limpiarTokens();
      await _borrarCache();
    }
  }

  Future<void> _borrarCache() async {
    try {
      await _borrarCacheMensajes?.call();
    } on Object {
      // Si la base local no abre, el cierre de sesión no debe fallar por eso.
    }
  }

  /// Solo borra el estado local. Se usa cuando el backend ya invalidó la sesión.
  Future<void> limpiarSesionLocal() => _almacen.limpiarTokens();

  Future<bool> get haySesionGuardada => _almacen.haySesion;

  Future<Perfil?> perfilGuardado() => _almacen.leerPerfil();

  Future<String?> _pushToken() async {
    try {
      return await _obtenerPushToken?.call();
    } on Object {
      return null;
    }
  }

  Future<T> _traducir<T>(Future<T> Function() accion) async {
    try {
      return await accion();
    } on DioException catch (e) {
      throw ApiError.deDio(e);
    }
  }
}
