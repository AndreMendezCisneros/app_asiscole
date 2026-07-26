import 'package:asiscole_app/core/error/api_error.dart';
import 'package:asiscole_app/core/error/error_codes.dart';
import 'package:asiscole_app/features/auth/data/auth_repository.dart';
import 'package:asiscole_app/features/auth/domain/perfil.dart';
import 'package:asiscole_app/features/auth/domain/sesion.dart';
import 'package:asiscole_app/features/auth/domain/solicitud_transferencia.dart';
import 'package:asiscole_app/features/auth/presentation/auth_cubit.dart';
import 'package:asiscole_app/features/auth/presentation/auth_state.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class AuthRepositoryMock extends Mock implements AuthRepository {}

const _telefono = '+51987654321';
const _documento = '70123456';

const _credenciales = CredencialesLogin(
  telefono: _telefono,
  documentoEstudiante: _documento,
);

final _perfil = const Perfil(
  telefono: '+51*****321',
  estado: EstadoCuenta.activo,
  estudianteActivoId: 1,
);

final _sesion = Sesion(
  sessionToken: 'session-1',
  dataToken: 'data-1',
  perfil: _perfil,
);

final _solicitud = SolicitudTransferencia(
  id: 'b7c1e0e2-1111-4222-8333-444455556666',
  estado: EstadoTransferencia.pendiente,
  expiraEn: DateTime.now().toUtc().add(const Duration(minutes: 5)),
);

void main() {
  late AuthRepositoryMock repositorio;

  setUp(() => repositorio = AuthRepositoryMock());

  AuthCubit crear() => AuthCubit(repositorio: repositorio);

  group('AuthCubit — 409 y traspaso de sesión', () {
    blocTest<AuthCubit, AuthState>(
      'un 409 lleva a LoginDenied y la solicitud a AwaitingTransferApproval',
      setUp: () {
        when(
          () => repositorio.login(
            telefono: _telefono,
            documentoEstudiante: _documento,
          ),
        ).thenThrow(
          const ApiError(
            codigo: CodigosError.sesionYaActiva,
            mensaje: 'Ya tienes una sesión activa en otro dispositivo.',
            statusCode: 409,
          ),
        );
        when(
          () => repositorio.solicitarTransferencia(
            telefono: _telefono,
            documentoEstudiante: _documento,
          ),
        ).thenAnswer((_) async => _solicitud);
      },
      build: crear,
      act: (cubit) async {
        await cubit.iniciarSesion(
          telefono: _telefono,
          documentoEstudiante: _documento,
        );
        await cubit.solicitarTransferencia();
      },
      expect: () => [
        const Authenticating(),
        const LoginDenied(
          credenciales: _credenciales,
          mensaje: 'Ya tienes una sesión activa en otro dispositivo.',
        ),
        const LoginDenied(
          credenciales: _credenciales,
          mensaje: 'Ya tienes una sesión activa en otro dispositivo.',
          solicitando: true,
        ),
        AwaitingTransferApproval(
          solicitud: _solicitud,
          credenciales: _credenciales,
        ),
      ],
    );

    blocTest<AuthCubit, AuthState>(
      'si el traspaso se aprueba, el login se reintenta solo',
      setUp: () {
        when(
          () => repositorio.login(
            telefono: _telefono,
            documentoEstudiante: _documento,
          ),
        ).thenAnswer((_) async => _sesion);
      },
      build: crear,
      seed: () => AwaitingTransferApproval(
        solicitud: _solicitud,
        credenciales: _credenciales,
      ),
      act: (cubit) => cubit.transferenciaResuelta(
        SolicitudTransferencia(
          id: _solicitud.id,
          estado: EstadoTransferencia.aprobada,
          expiraEn: _solicitud.expiraEn,
        ),
      ),
      expect: () => [const Authenticating(), OnlineSync(_perfil)],
    );

    blocTest<AuthCubit, AuthState>(
      'un rechazo devuelve al login con explicación',
      build: crear,
      seed: () => AwaitingTransferApproval(
        solicitud: _solicitud,
        credenciales: _credenciales,
      ),
      act: (cubit) => cubit.transferenciaResuelta(
        SolicitudTransferencia(
          id: _solicitud.id,
          estado: EstadoTransferencia.rechazada,
        ),
      ),
      expect: () => [isA<Unauthenticated>()],
    );

    blocTest<AuthCubit, AuthState>(
      'si la solicitud choca con el límite, se queda en LoginDenied con el código',
      setUp: () {
        when(
          () => repositorio.solicitarTransferencia(
            telefono: _telefono,
            documentoEstudiante: _documento,
          ),
        ).thenThrow(
          ApiError.local(CodigosError.demasiadasSolicitudes, statusCode: 429),
        );
      },
      build: crear,
      seed: () => const LoginDenied(
        credenciales: _credenciales,
        mensaje: 'Ya tienes una sesión activa en otro dispositivo.',
      ),
      act: (cubit) => cubit.solicitarTransferencia(),
      expect: () => [
        const LoginDenied(
          credenciales: _credenciales,
          mensaje: 'Ya tienes una sesión activa en otro dispositivo.',
          solicitando: true,
        ),
        const LoginDenied(
          credenciales: _credenciales,
          mensaje: 'Ya tienes una sesión activa en otro dispositivo.',
          errorSolicitud: CodigosError.demasiadasSolicitudes,
        ),
      ],
    );
  });

  group('AuthCubit — cuenta suspendida', () {
    blocTest<AuthCubit, AuthState>(
      'un 403 ACCOUNT_SUSPENDED muestra el motivo del backend',
      setUp: () {
        when(
          () => repositorio.login(
            telefono: _telefono,
            documentoEstudiante: _documento,
          ),
        ).thenThrow(
          const ApiError(
            codigo: CodigosError.cuentaSuspendida,
            mensaje: 'Deuda pendiente con tesorería.',
            statusCode: 403,
          ),
        );
      },
      build: crear,
      act: (cubit) => cubit.iniciarSesion(
        telefono: _telefono,
        documentoEstudiante: _documento,
      ),
      expect: () => [
        const Authenticating(),
        const Suspended(motivo: 'Deuda pendiente con tesorería.'),
      ],
    );
  });
}
