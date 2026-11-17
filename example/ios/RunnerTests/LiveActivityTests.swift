import Flutter
import XCTest

@testable import pushpilot_flutter

/// handleLiveActivityURL through the plugin's channel handler, against the real iOS SDK.
class LiveActivityTests: XCTestCase {
  /// Sends one channel call to a new plugin and returns its answer.
  private func answer(_ method: String, _ arguments: Any?) -> Any? {
    let done = expectation(description: "result")
    var answer: Any?
    PushpilotFlutterPlugin().handle(FlutterMethodCall(methodName: method, arguments: arguments)) { result in
      answer = result
      done.fulfill()
    }
    waitForExpectations(timeout: 1)
    return answer
  }

  /// A URL that is not from a live activity comes back unchanged.
  func testOtherUrlsComeBackUnchanged() {
    XCTAssertEqual(answer("handleLiveActivityURL", "https://example.com/orders/42") as? String,
                   "https://example.com/orders/42")
  }

  /// A live activity tap with no link of its own (the SDK's placeholder URL) returns nil: just open the app.
  func testPlaceholderLinkReturnsNil() {
    XCTAssertNil(answer("handleLiveActivityURL", "pushpilot-live://open?pushpilot_live=abc"))
  }

  /// A live activity tap returns the activity's link without PushPilot's marker.
  func testMarkerIsRemoved() {
    XCTAssertEqual(answer("handleLiveActivityURL", "https://example.com/orders/42?pushpilot_live=abc") as? String,
                   "https://example.com/orders/42")
  }

  /// A non-string argument is refused rather than guessed at.
  func testBadArgumentIsAnError() {
    XCTAssertEqual((answer("handleLiveActivityURL", 42) as? FlutterError)?.code, "bad_arguments")
  }
}
