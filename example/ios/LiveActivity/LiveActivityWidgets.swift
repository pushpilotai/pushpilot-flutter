import PushPilotLive
import SwiftUI
import WidgetKit

/// The example's Widget Extension: PushPilot's default widget draws every PushPilot live activity on the
/// Lock Screen and in the Dynamic Island. The App Group is the one the app passes to PushPilot's init.
@main
struct LiveActivityWidgets: WidgetBundle {
  var body: some Widget {
    PushPilotLiveActivityWidget(appGroup: "group.ai.pushpilot.pushpilotFlutterExample")
  }
}
