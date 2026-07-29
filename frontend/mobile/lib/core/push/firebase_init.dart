import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

/// Inicializa Firebase una sola vez por isolate.
///
/// En Android el isolate de FCM background puede crear `[DEFAULT]` en el
/// proceso nativo antes que el isolate principal; `Firebase.apps.isEmpty` no
/// lo detecta y un segundo `initializeApp` lanza `duplicate-app`.
Future<void> asegurarFirebaseApp() async {
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') return;
    rethrow;
  }
}
