import Flutter
import UIKit
import XCTest

@testable import pushpilot_flutter

/// The coach-mark stand-ins the plugin keeps for PushPilotMark widgets, and showInApp's channel handling.
@MainActor
class InAppTests: XCTestCase {
  /// A mark becomes a clear, untouchable view at the rect, inside the host; moving it reuses the same view.
  func testMarkPlacesOneStandInPerName() {
    let plugin = PushpilotFlutterPlugin()
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    plugin.mark("compose", at: CGRect(x: 10, y: 20, width: 100, height: 40), in: host)
    let view = plugin.marks["compose"]
    XCTAssertTrue(view?.superview === host)
    XCTAssertEqual(view?.frame, CGRect(x: 10, y: 20, width: 100, height: 40))
    XCTAssertEqual(view?.isUserInteractionEnabled, false)
    XCTAssertEqual(view?.backgroundColor, .clear)
    // The SDK skips a view with alpha under 0.01 as invisible, so the stand-in keeps alpha 1.
    XCTAssertEqual(view?.alpha, 1)
    plugin.mark("compose", at: CGRect(x: 30, y: 50, width: 100, height: 40), in: host)
    XCTAssertTrue(plugin.marks["compose"] === view)
    XCTAssertEqual(host.subviews.count, 1)
    XCTAssertEqual(view?.frame.origin, CGPoint(x: 30, y: 50))
  }

  /// Unmarking removes the stand-in from the host.
  func testUnmarkRemovesTheStandIn() {
    let plugin = PushpilotFlutterPlugin()
    let host = UIView()
    plugin.mark("compose", at: CGRect(x: 0, y: 0, width: 10, height: 10), in: host)
    plugin.unmark("compose")
    XCTAssertNil(plugin.marks["compose"])
    XCTAssertTrue(host.subviews.isEmpty)
  }

  /// showInApp before the SDK has a cached message answers false through the channel, and a bad argument errors.
  func testShowInAppThroughTheChannel() {
    let done = expectation(description: "results")
    done.expectedFulfillmentCount = 2
    let plugin = PushpilotFlutterPlugin()
    plugin.handle(FlutterMethodCall(methodName: "showInApp", arguments: "nothing-cached")) { result in
      XCTAssertEqual(result as? Bool, false)
      done.fulfill()
    }
    plugin.handle(FlutterMethodCall(methodName: "showInApp", arguments: 42)) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "bad_arguments")
      done.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
