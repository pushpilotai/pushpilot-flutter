import Flutter
import Foundation
import PushPilot

/// Passes each Dart call straight to the native PushPilot SDK, which does all the work.
public class PushpilotFlutterPlugin: NSObject, FlutterPlugin {
  private let badArguments = FlutterError(code: "bad_arguments", message: "unexpected argument type", details: nil)

  /// Listens on the channel the Dart side calls.
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ai.pushpilot/sdk", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PushpilotFlutterPlugin(), channel: channel)
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
    case "setPushToken":
      PushPilot.setPushToken(call.arguments as? String)
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
    default:
      return result(FlutterMethodNotImplemented)
    }
    result(nil)
  }
}
