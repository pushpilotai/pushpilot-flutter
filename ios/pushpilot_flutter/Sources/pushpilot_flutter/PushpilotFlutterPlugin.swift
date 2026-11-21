import Flutter
import Foundation
import PushPilot
import UIKit
import UserNotifications

/// Passes each Dart call straight to the native PushPilot SDK, and does the app-delegate work a native app
/// would: registers for the APNs device token, hands it to the SDK, and forwards notification taps.
public class PushpilotFlutterPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let badArguments = FlutterError(code: "bad_arguments", message: "unexpected argument type", details: nil)
  let gate = DartGate()
  private var dartHandlesLinks = false
  private var dartHandlesTaps = false
  private var channel: FlutterMethodChannel?
  /// Gives the Flutter view controller whose view holds the coach-mark stand-ins; the engine owns it.
  private weak var registrar: FlutterPluginRegistrar?
  /// Stand-ins for Dart's PushPilotMark widgets by name: transparent views the SDK can point coach marks at.
  private(set) var marks: [String: UIView] = [:]

  /// Listens on the channel the Dart side calls and on the app's delegate calls.
  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = PushpilotFlutterPlugin()
    let channel = FlutterMethodChannel(name: "ai.pushpilot/sdk", binaryMessenger: registrar.messenger())
    plugin.channel = channel
    plugin.registrar = registrar
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.addApplicationDelegate(plugin)
    // With scenes, the tap that launches a killed app arrives with the scene connection.
    registrar.addSceneDelegate(plugin)
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
    guard PushPilot.handleNotificationResponse(response) else { return }
    tapped(response, opensApp: UIApplication.shared.applicationState != .background)
    completionHandler()
  }

  /// Forwards the tap that launched the app; the SDK counts a tap that also reaches `didReceive` once.
  public func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                    options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
    if let response = connectionOptions?.notificationResponse, PushPilot.handleNotificationResponse(response) {
      tapped(response, opensApp: true)
    }
    return false // other plugins may want the connection too
  }

  /// Passes a tap that opened the app to Dart, once per notification. A button without a link only wakes
  /// the app in the background (`opensApp` false), as on Android where it never reaches the app.
  private func tapped(_ response: UNNotificationResponse, opensApp: Bool) {
    let userInfo = response.notification.request.content.userInfo
    guard opensApp, response.actionIdentifier != UNNotificationDismissActionIdentifier,
          let id = userInfo["notification_id"] as? String, gate.firstTap(id) else { return }
    let data = userInfo["data"] as? [String: String] ?? [:]
    gate.run { [weak self] in
      guard let self, self.dartHandlesTaps else { return }
      self.channel?.invokeMethod("onTap", arguments: ["notificationId": id, "data": data])
    }
  }

  /// A PushPilot link from the SDK, on the main thread: it waits for Dart's init, then goes to Dart or iOS.
  private func receive(_ url: URL) {
    gate.run { [weak self] in
      guard let self else { return }
      if self.dartHandlesLinks {
        self.channel?.invokeMethod("onLink", arguments: url.absoluteString)
      } else {
        UIApplication.shared.open(url)
      }
    }
  }

  /// Runs one SDK call; the SDK returns at once and never throws.
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      let args = call.arguments as? [String: Any] ?? [:]
      let sdkKey = args["sdkKey"] as? String ?? ""
      let appGroup = args["appGroup"] as? String
      if let baseUrl = args["baseUrl"] as? String {
        // Falling back to the default server would send a self-hosted app's data elsewhere, so refuse.
        guard let url = URL(string: baseUrl) else {
          return result(FlutterError(code: "invalid_base_url", message: "baseUrl is not a URL", details: nil))
        }
        PushPilot.initialize(sdkKey: sdkKey, baseUrl: url, appGroup: appGroup)
      } else {
        PushPilot.initialize(sdkKey: sdkKey, appGroup: appGroup)
      }
      gate.start()
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
    case "track":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let name = args["name"] as? String else { return result(badArguments) }
      PushPilot.track(name, properties: args["properties"] as? [String: Any] ?? [:])
    case "setTopics":
      guard let topics = call.arguments as? [String] else { return result(badArguments) }
      PushPilot.setTopics(topics)
    case "logout":
      PushPilot.logout()
    case "forget":
      PushPilot.forget()
    case "setLinkHandler":
      dartHandlesLinks = call.arguments as? Bool ?? false
    case "setTapHandler":
      dartHandlesTaps = call.arguments as? Bool ?? false
    case "handleLiveActivityURL":
      // A live activity tap is counted and its own link returned (nil: none); other URLs come back unchanged.
      guard let link = call.arguments as? String else { return result(badArguments) }
      guard let url = URL(string: link) else { return result(link) }
      return result(PushPilot.handleLiveActivityURL(url)?.absoluteString)
    case "showInApp":
      guard let name = call.arguments as? String else { return result(badArguments) }
      // Flutter calls plugins on the main thread, where the SDK's in-app calls must run.
      return result(MainActor.assumeIsolated { PushPilot.showInApp(name) })
    case "markView":
      guard let args = call.arguments as? [String: Any], let name = args["name"] as? String,
            let x = args["x"] as? Double, let y = args["y"] as? Double,
            let width = args["width"] as? Double, let height = args["height"] as? Double else {
        return result(badArguments)
      }
      // No view controller (a headless engine): nothing on screen to point at.
      if let host = registrar?.viewController?.view {
        mark(name, at: CGRect(x: x, y: y, width: width, height: height), in: host)
      }
    case "unmarkView":
      guard let name = call.arguments as? String else { return result(badArguments) }
      unmark(name)
    default:
      return result(FlutterMethodNotImplemented)
    }
    result(nil)
  }
}

extension PushpilotFlutterPlugin {
  /// Places the stand-in for a PushPilotMark at `rect` (points from the Flutter view's top left) in `host`, the
  /// Flutter view, and names it for the SDK. It draws nothing and takes no touches, so Flutter's UI works as
  /// before; it stays opaque to the SDK's visibility check (alpha 1, clear background). Main thread only.
  func mark(_ name: String, at rect: CGRect, in host: UIView) {
    let view = marks[name] ?? UIView()
    view.isUserInteractionEnabled = false
    view.backgroundColor = .clear
    if view.superview !== host { host.addSubview(view) }
    view.frame = rect
    marks[name] = view
    MainActor.assumeIsolated { PushPilot.markView(view, name: name) }
  }

  /// Forgets the mark `name` in the SDK and removes its stand-in. Main thread only.
  func unmark(_ name: String) {
    MainActor.assumeIsolated { PushPilot.unmarkView(name: name) }
    marks.removeValue(forKey: name)?.removeFromSuperview()
  }
}

/// Holds work for Dart until Dart's `init`: a tap that launches the app arrives before Dart runs, and by
/// `init` Dart has said whether it handles links and taps (it sets its handlers first). Main thread only.
final class DartGate {
  private var started = false
  private var waiting: [() -> Void] = []
  private var seen: Set<String> = []

  /// Runs [work] now, or once Dart starts.
  func run(_ work: @escaping () -> Void) {
    if started { work() } else { waiting.append(work) }
  }

  /// Marks Dart as started and runs what waited, in arrival order.
  func start() {
    started = true
    let ready = waiting
    waiting = []
    ready.forEach { $0() }
  }

  /// True the first time a notification id is seen in this process.
  func firstTap(_ notificationId: String) -> Bool {
    seen.insert(notificationId).inserted
  }
}
