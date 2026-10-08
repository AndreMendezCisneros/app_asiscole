import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Sin esto flutter_local_notifications no muestra avisos con la app abierta.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    excluirDocumentosDelRespaldo()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// sqflite guarda la caché de mensajes en Documents, que iCloud respalda.
  /// Lleva nombres de menores: no debe salir del teléfono (Ley 29733), igual
  /// que en Android con `allowBackup=false`.
  private func excluirDocumentosDelRespaldo() {
    guard var documentos = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask
    ).first else { return }
    var valores = URLResourceValues()
    valores.isExcludedFromBackup = true
    try? documentos.setResourceValues(valores)
  }
}
