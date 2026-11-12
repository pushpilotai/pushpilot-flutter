import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Makes this delegate the notification center's, so every plugin (PushPilot among them) gets taps.
  /// Needed here because firebase_messaging would otherwise take the notification center for itself.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Registers the plugins, and the example's own permission prompt, which PushPilot never shows.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ExamplePermission") else { return }
    FlutterMethodChannel(name: "pushpilot_example/permission", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { _, result in
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        result(nil)
      }
  }
}
