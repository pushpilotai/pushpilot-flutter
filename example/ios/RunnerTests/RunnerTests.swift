import Flutter
import UIKit
import XCTest

@testable import pushpilot_flutter

/// Unit tests for the plugin's own iOS glue; the SDK calls themselves are covered by the native SDK's tests.
class RunnerTests: XCTestCase {
  /// Collects where each link was sent.
  private var sent: [(String, Bool)] = []
  private func deliver(_ url: URL, toDart: Bool) { sent.append((url.absoluteString, toDart)) }

  /// A link from a tap that launched the app waits for Dart's init, then goes to the Dart handler.
  func testLinkBeforeInitWaitsForDart() {
    var gate = LinkGate()
    gate.arrived(URL(string: "https://example.com/a")!, deliver: deliver)
    XCTAssertTrue(sent.isEmpty)
    gate.dartHandlesLinks = true
    gate.dartStarted(deliver: deliver)
    XCTAssertEqual(sent.map(\.0), ["https://example.com/a"])
    XCTAssertEqual(sent.map(\.1), [true])
  }

  /// Without a Dart handler the link goes to iOS, before or after init.
  func testLinkWithoutDartHandlerGoesToSystem() {
    var gate = LinkGate()
    gate.arrived(URL(string: "myapp://x")!, deliver: deliver)
    gate.dartStarted(deliver: deliver)
    gate.arrived(URL(string: "myapp://y")!, deliver: deliver)
    XCTAssertEqual(sent.map(\.0), ["myapp://x", "myapp://y"])
    XCTAssertEqual(sent.map(\.1), [false, false])
  }

  /// setPushToken from Dart is refused on iOS, where the plugin passes the APNs token itself.
  func testSetPushTokenIsUnsupported() {
    let done = expectation(description: "result")
    PushpilotFlutterPlugin().handle(FlutterMethodCall(methodName: "setPushToken", arguments: "x")) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "unsupported")
      done.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
