import 'package:get_it/get_it.dart';

import '../../features/asistencias/data/asistencias_api.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/session_storage.dart';
import '../../features/auth/presentation/auth_cubit.dart';
import '../../features/incidencias/data/incidencias_api.dart';
import '../../features/mensajes/data/mensajes_api.dart';
import '../../features/mensajes/data/mensajes_repository.dart';
import '../../features/notas/data/notas_api.dart';
import '../../features/perfil/data/perfil_repository.dart';
import '../config/feature_flags.dart';
import '../connectivity/network_info.dart';
import '../device/info_dispositivo.dart';
import '../network/api_client.dart';
import '../push/servicio_push.dart';
import '../session/eventos_sesion.dart';
import '../storage/local_db.dart';
import '../storage/secure_storage.dart';
import '../storage/token_store.dart';
import '../theme/preferencia_tema.dart';
import '../version/version_app_api.dart';

final GetIt sl = GetIt.instance;

/// Registra las dependencias. Es síncrono a propósito: lo que necesite red o
/// canal de plataforma se resuelve después del primer frame.
Future<void> configurarInyector() async {
  sl.registerLazySingleton<SecureStorage>(SecureStorage.new);
  sl.registerLazySingleton<LocalDb>(LocalDb.new);
  sl.registerLazySingleton<NetworkInfo>(NetworkInfo.new);
  sl.registerLazySingleton<InfoDispositivo>(InfoDispositivo.new);
  sl.registerLazySingleton<EventosSesion>(EventosSesion.new);
  sl.registerLazySingleton<PreferenciaTema>(PreferenciaTema.new);
  sl.registerLazySingleton<ServicioPush>(ServicioPush.new);

  sl.registerLazySingleton<SessionStorage>(() => SessionStorage(sl()));
  sl.registerLazySingleton<TokenStore>(() => sl<SessionStorage>());

  sl.registerLazySingleton<ApiClient>(
    () => ApiClient(
      tokens: sl<TokenStore>(),
      refrescar: () async {
        final emitido = await sl<AuthApi>().refrescarDatos();
        return (token: emitido.dataToken, expiraEn: emitido.dataExpiraEn);
      },
      alInvalidarSesion: sl<EventosSesion>().sesionInvalidada,
    ),
  );

  sl.registerLazySingleton<VersionAppApi>(() => VersionAppApi(sl()));

  sl.registerLazySingleton<AuthApi>(() => AuthApi(sl<ApiClient>().dio));
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepository(
      api: sl(),
      almacen: sl(),
      dispositivo: sl(),
      obtenerPushToken: sl<ServicioPush>().token,
      borrarCacheMensajes: sl<LocalDb>().vaciar,
      revocarPushToken: sl<ServicioPush>().revocarToken,
    ),
  );
  sl.registerLazySingleton<AuthCubit>(
    () => AuthCubit(repositorio: sl(), red: sl(), eventos: sl()),
  );

  sl.registerLazySingleton<FeatureFlags>(() => FeatureFlags(sl<ApiClient>()));

  sl.registerLazySingleton(() => MensajesApi(sl<ApiClient>().dio));
  sl.registerLazySingleton(
    () => MensajesRepository(api: sl(), local: sl(), red: sl()),
  );
  sl.registerLazySingleton(() => AsistenciasApi(sl<ApiClient>().dio));
  sl.registerLazySingleton(() => IncidenciasApi(sl<ApiClient>().dio));
  sl.registerLazySingleton(() => NotasApi(sl<ApiClient>().dio));
  sl.registerLazySingleton(() => PerfilRepository(sl<ApiClient>().dio));
}
