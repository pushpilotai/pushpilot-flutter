import Flutter
import Foundation
import PushPilot
import UIKit
import UserNotifications

/// Passes each Dart call straight to the native PushPilot SDK, and does the app-delegate work a native app
/// would: registers for the APNs device token, hands it to the SDK, and forwards notification taps.
public class PushpilotFlutterPlugin: NSObject, FlutterPlugin {
  private let badArguments = FlutterError(code: "bad_arguments", message: "unexpected argument type", details: nil)
  private var links = LinkGate()
  private var channel: FlutterMethodChannel?

  /// Listens on the channel the Dart side calls and on the app's delegate calls.
  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = PushpilotFlutterPlugin()
    let channel = FlutterMethodChannel(name: "ai.pushpilot/sdk", binaryMessenger: registrar.messenger())
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.addApplicationDelegate(plugin)
    // FlutterAppDelegate forwards notification-center calls to plugins once it is the center's delegate.
    // An app or plugin that set its own delegate keeps it; the README says what to do then.
    let center = UNUserNotificationCenter.current()
    if center.delegate == nil,
       let app = UIApplication.shared.delegate as? (UNUserNotificationCenterDelegate & FlutterAppLifeCycleProvider) {
      center.delegate = app
    }
    PushPilot.setLinkHandler { [weak plugin] url in plugin?.receive(url) }
    // A permission granted in the system alert shows up when the app is active again.
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                           queue: .main) { _ in registerIfAllowed() }
    registerIfAllowed()
  }

  /// Asks iOS for the device token once notifications are allowed; PushPilot itself never prompts.
  private static func registerIfAllowed() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
      DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    }
  }

  /// Hands the APNs device token to the SDK as is.
  public func application(_ application: UIApplication,
                          didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    PushPilot.setPushToken(deviceToken)
  }

  /// Forwards a tap to the SDK, which records the click and opens the link; other pushes are left to others.
  public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                     withCompletionHandler completionHandler: @escaping () -> Void) {
    // Every plugin gets this call with the same handler, so only the push's owner completes it.
    if PushPilot.handleNotificationResponse(response) { completionHandler() }
  }

  /// A PushPilot link from the SDK, on the main thread.
  private func receive(_ url: URL) {
    links.arrived(url, deliver: deliver)
  }

  /// Gives a link to the Dart handler, or to iOS when Dart has none.
  private func deliver(_ url: URL, toDart: Bool) {
    if toDart {
      channel?.invokeMethod("onLink", arguments: url.absoluteString)
    } else {
      UIApplication.shared.open(url)
    }
  }

  /// Runs one SDK call; the SDK returns at once and never throws.
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      let args = call.arguments as? [String: Any] ?? [:]
      let sdkKey = args["sdkKey"] as? String ?? ""
      if let baseUrl = args["baseUrl"] as? String {
        // Falling back to the default server would send a self-hosted app's data elsewhere, so refuse.
        guard let url = URL(string: baseUrl) else {
          return result(FlutterError(code: "invalid_base_url", message: "baseUrl is not a URL", details: nil))
        }
        PushPilot.initialize(sdkKey: sdkKey, baseUrl: url)
      } else {
        PushPilot.initialize(sdkKey: sdkKey)
      }
      links.dartStarted(deliver: deliver)
    case "setPushToken":
      return result(FlutterError(code: "unsupported",
                                 message: "On iOS the plugin passes the APNs device token itself", details: nil))
    case "setExternalUserId":
      // The iOS SDK takes a non-optional id; clearing it is what logout does.
      if let id = call.arguments as? String { PushPilot.setExternalUserId(id) } else { PushPilot.logout() }
    case "setAttributes":
      // The channel turns Dart null into NSNull, which the SDK treats as "remove".
      guard let attributes = call.arguments as? [String: Any] else { return result(badArguments) }
      PushPilot.setAttributes(attributes)
    case "setTopics":
      guard let topics = call.arguments as? [String] else { return result(badArguments) }
      PushPilot.setTopics(topics)
    case "logout":
      PushPilot.logout()
    case "forget":
      PushPilot.forget()
    case "setLinkHandler":
      links.dartHandlesLinks = call.arguments as? Bool ?? false
    default:
      return result(FlutterMethodNotImplemented)
    }
    result(nil)
  }
}

/// Decides where a tapped link goes. A tap that launches the app arrives before Dart runs, so links wait
/// until Dart's `init`; by then Dart has said whether it handles links (it sets its handler first).
struct LinkGate {
  var dartHandlesLinks = false
  private var started = false
  private var waiting: [URL] = []

  /// Delivers [url] now, or keeps it until Dart starts.
  mutating func arrived(_ url: URL, deliver: (URL, Bool) -> Void) {
    if started { deliver(url, dartHandlesLinks) } else { waiting.append(url) }
  }

  /// Marks Dart as started and delivers the links that were waiting.
  mutating func dartStarted(deliver: (URL, Bool) -> Void) {
    started = true
    waiting.forEach { deliver($0, dartHandlesLinks) }
    waiting = []
  }
}
