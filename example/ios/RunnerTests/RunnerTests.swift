import Flutter
import UIKit
import XCTest

@testable import pushpilot_flutter

/// Unit tests for the plugin's own iOS glue; the SDK calls themselves are covered by the native SDK's tests.
class RunnerTests: XCTestCase {
  /// Work from before init (a launch tap's link and tap) waits, then runs in arrival order; later work runs at once.
  func testWorkWaitsForInitThenRunsInOrder() {
    let gate = DartGate()
    var ran: [String] = []
    gate.run { ran.append("link") }
    gate.run { ran.append("tap") }
    XCTAssertTrue(ran.isEmpty)
    gate.start()
    gate.run { ran.append("later") }
    XCTAssertEqual(ran, ["link", "tap", "later"])
  }

  /// A notification reaching the plugin twice (scene connection and didReceive) is passed on once.
  func testEachTapCountsOnce() {
    let gate = DartGate()
    XCTAssertTrue(gate.firstTap("n1"))
    XCTAssertFalse(gate.firstTap("n1"))
    XCTAssertTrue(gate.firstTap("n2"))
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
