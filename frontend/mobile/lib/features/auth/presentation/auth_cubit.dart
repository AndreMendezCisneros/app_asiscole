import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/env.dart';
import '../../../core/connectivity/network_info.dart';
import '../../../core/di/injector.dart';
import '../../../core/error/api_error.dart';
import '../../../core/error/error_codes.dart';
import '../../../core/session/eventos_sesion.dart';
import '../../perfil/data/perfil_repository.dart';
import '../data/auth_repository.dart';
import '../domain/solicitud_transferencia.dart';
import 'auth_state.dart';

/// Gobierna la máquina de estados de la sesión (SRS 7.3).
class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required AuthRepository repositorio,
    NetworkInfo? red,
    EventosSesion? eventos,
  })  : _repositorio = repositorio,
        _red = red,
        super(const Unauthenticated()) {
    _suscripcionEventos = eventos?.invalidaciones.listen(_sesionInvalidada);
    _suscripcionRed = _red?.cambios.listen(cambioDeConexion);
  }

  final AuthRepository _repositorio;
  final NetworkInfo? _red;

  StreamSubscription<ApiError>? _suscripcionEventos;
  StreamSubscription<bool>? _suscripcionRed;
  Timer? _sondeoTransferencia;

  /// Restaura la sesión guardada al abrir la app.
  Future<void> iniciar() async {
    emit(const Authenticating());

    if (!await _repositorio.haySesionGuardada) {
      emit(const Unauthenticated());
      return;
    }

    var perfil = await _repositorio.perfilGuardado();
    if (perfil != null && perfil.estaSuspendido) {
      await _repositorio.limpiarSesionLocal();
      emit(Suspended(motivo: perfil.motivoSuspension));
      return;
    }

    final hayRed = await (_red?.hayConexion ?? Future.value(true));
    if (!hayRed) {
      emit(OfflineMessagesOnly(perfil));
      return;
    }

    try {
      await _repositorio.refrescarDatosAlArranque();
    } on ApiError catch (e) {
      if (e.codigo == CodigosError.sesionExpirada ||
          e.codigo == CodigosError.noAutenticado) {
        emit(Unauthenticated(codigoError: e.codigo, mensaje: e.mensaje));
        return;
      }
      // Fallo de red u otro: si hay perfil cacheado, seguimos; si no, intentamos
      // recuperar perfil más abajo.
    } catch (_) {
      // Misma política: no borrar sesión solo por un fallo puntual.
    }

    if (perfil == null) {
      try {
        perfil = await sl<PerfilRepository>().obtener(forzar: true);
        await _repositorio.guardarPerfil(perfil);
      } on ApiError catch (e) {
        if (e.codigo == CodigosError.sesionExpirada ||
            e.codigo == CodigosError.noAutenticado) {
          await _repositorio.limpiarSesionLocal();
          emit(Unauthenticated(codigoError: e.codigo, mensaje: e.mensaje));
          return;
        }
        await _repositorio.limpiarSesionLocal();
        emit(const Unauthenticated());
        return;
      } catch (_) {
        await _repositorio.limpiarSesionLocal();
        emit(const Unauthenticated());
        return;
      }
    }

    emit(OnlineSync(perfil));
    unawaited(_repositorio.renovarSesionSiCorresponde());
  }

  Future<void> iniciarSesion({
    required String telefono,
    required String documentoEstudiante,
  }) async {
    final credenciales = CredencialesLogin(
      telefono: telefono,
      documentoEstudiante: documentoEstudiante,
    );
    emit(const Authenticating());

    try {
      final sesion = await _repositorio.login(
        telefono: credenciales.telefono,
        documentoEstudiante: credenciales.documentoEstudiante,
      );
      emit(OnlineSync(sesion.perfil));
    } on ApiError catch (e) {
      emit(_estadoParaFalloDeLogin(e, credenciales));
    }
  }

  AuthState _estadoParaFalloDeLogin(ApiError e, CredencialesLogin cred) {
    switch (e.codigo) {
      case CodigosError.sesionYaActiva:
        return LoginDenied(credenciales: cred, mensaje: e.mensaje);
      case CodigosError.cuentaSuspendida:
        return Suspended(motivo: e.mensaje);
      default:
        return Unauthenticated(codigoError: e.codigo, mensaje: e.mensaje);
    }
  }

  /// Pide el traspaso desde el dispositivo denegado (RF-A09).
  Future<void> solicitarTransferencia() async {
    final actual = state;
    if (actual is! LoginDenied) return;

    emit(actual.copyWith(solicitando: true));
    try {
      final solicitud = await _repositorio.solicitarTransferencia(
        telefono: actual.credenciales.telefono,
        documentoEstudiante: actual.credenciales.documentoEstudiante,
      );
      emit(
        AwaitingTransferApproval(
          solicitud: solicitud,
          credenciales: actual.credenciales,
        ),
      );
    } on ApiError catch (e) {
      emit(actual.copyWith(solicitando: false, errorSolicitud: e.codigo));
    }
  }

  /// Sondea `GET /auth/session-transfer/{id}` mientras se espera la respuesta
  /// del dispositivo activo.
  void iniciarSondeoTransferencia() {
    _sondeoTransferencia?.cancel();
    _sondeoTransferencia = Timer.periodic(
      Env.intervaloSondeoTransferencia,
      (_) => consultarTransferencia(),
    );
  }

  void detenerSondeoTransferencia() {
    _sondeoTransferencia?.cancel();
    _sondeoTransferencia = null;
  }

  Future<void> consultarTransferencia() async {
    final actual = state;
    if (actual is! AwaitingTransferApproval) {
      detenerSondeoTransferencia();
      return;
    }

    try {
      final solicitud =
          await _repositorio.consultarTransferencia(actual.solicitud.id);
      await transferenciaResuelta(solicitud);
    } on ApiError catch (e) {
      if (e.codigo == CodigosError.transferenciaExpirada) {
        detenerSondeoTransferencia();
        emit(
          Unauthenticated(codigoError: e.codigo, mensaje: e.mensaje),
        );
      }
      // Un fallo de red puntual no cancela la espera: el siguiente ciclo
      // vuelve a intentarlo mientras quede tiempo.
    }
  }

  /// Resultado del sondeo de `GET /auth/session-transfer/{id}`.
  Future<void> transferenciaResuelta(SolicitudTransferencia solicitud) async {
    final actual = state;
    if (actual is! AwaitingTransferApproval) return;

    switch (solicitud.estado) {
      case EstadoTransferencia.pendiente:
        emit(
          AwaitingTransferApproval(
            solicitud: solicitud,
            credenciales: actual.credenciales,
          ),
        );
      case EstadoTransferencia.aprobada:
        detenerSondeoTransferencia();
        await iniciarSesion(
          telefono: actual.credenciales.telefono,
          documentoEstudiante: actual.credenciales.documentoEstudiante,
        );
      case EstadoTransferencia.rechazada:
        detenerSondeoTransferencia();
        emit(
          const Unauthenticated(
            codigoError: 'TRANSFER_REJECTED',
            mensaje:
                'El otro dispositivo rechazó el acceso. Puedes intentarlo de nuevo '
                'o pedir al colegio que cierre la sesión anterior.',
          ),
        );
      case EstadoTransferencia.expirada:
        detenerSondeoTransferencia();
        emit(
          Unauthenticated(
            codigoError: CodigosError.transferenciaExpirada,
            mensaje: CodigosError.mensajePorDefecto(
              CodigosError.transferenciaExpirada,
            ),
          ),
        );
    }
  }

  /// El dispositivo que tiene la sesión aprueba el traspaso: aquí se cierra.
  /// Devuelve `null` si todo fue bien o el código del error.
  Future<String?> aprobarTransferenciaEntrante(String id) async {
    try {
      await _repositorio.aprobarTransferencia(id);
    } on ApiError catch (e) {
      return e.codigo;
    }
    emit(
      const Unauthenticated(
        mensaje: 'Cerraste la sesión en este dispositivo al permitir el acceso '
            'en el otro equipo.',
      ),
    );
    return null;
  }

  /// Devuelve `null` si el rechazo se registró o el código del error.
  Future<String?> rechazarTransferenciaEntrante(String id) async {
    try {
      await _repositorio.rechazarTransferencia(id);
      return null;
    } on ApiError catch (e) {
      return e.codigo;
    }
  }

  Future<void> cerrarSesion() async {
    await _repositorio.cerrarSesion();
    sl<PerfilRepository>().invalidarCache();
    emit(const Unauthenticated());
  }

  /// Vuelve al formulario limpio, por ejemplo al cancelar una espera.
  void volverALogin() {
    detenerSondeoTransferencia();
    emit(const Unauthenticated());
  }

  void cambioDeConexion(bool hayRed) {
    final actual = state;
    if (hayRed && actual is OfflineMessagesOnly && actual.perfil != null) {
      emit(OnlineSync(actual.perfil!));
      return;
    }
    if (!hayRed && actual is OnlineSync) {
      emit(OfflineMessagesOnly(actual.perfil));
    }
  }

  Future<void> _sesionInvalidada(ApiError motivo) async {
    await _repositorio.limpiarSesionLocal();
    sl<PerfilRepository>().invalidarCache();
    if (motivo.codigo == CodigosError.cuentaSuspendida) {
      emit(Suspended(motivo: motivo.mensaje));
      return;
    }
    emit(Unauthenticated(codigoError: motivo.codigo, mensaje: motivo.mensaje));
  }

  @override
  Future<void> close() async {
    detenerSondeoTransferencia();
    await _suscripcionEventos?.cancel();
    await _suscripcionRed?.cancel();
    return super.close();
  }
}
