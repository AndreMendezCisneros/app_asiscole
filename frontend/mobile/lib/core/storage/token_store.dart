/// Contrato mínimo de tokens que necesita la capa de red.
///
/// La implementación real vive en `features/auth/data/session_storage.dart`.
/// Se declara aquí para que el interceptor no dependa de una feature.
abstract class TokenStore {
  /// Token de sesión (10 días). Solo se envía a `/auth/*`.
  Future<String?> leerSessionToken();

  /// Token de datos (15 a 60 min). Lo llevan los endpoints de negocio.
  Future<String?> leerDataToken();

  Future<void> guardarDataToken(String token, DateTime? expiraEn);

  /// Borra ambos tokens. No toca la caché de mensajes.
  Future<void> limpiarTokens();
}
