## 2.2.0 (unreleased)

* Wraps the PushPilot Android and iOS SDKs 2.2.0, which show in-app messages from the dashboard: HTML pages over the app, on app open with no Dart code.
* `showInApp(name) → Future<bool>`: shows the first eligible cached message with that in-app trigger name, on the platform's main thread; `true` when one is now on screen.
* `PushPilotMark(name:, child:)`: names a widget as a coach-mark target. The plugin keeps a transparent, untouchable native view at the widget's rect inside the Flutter view and marks it with the native `markView`.
* Links opened by in-app messages reach `setLinkHandler`'s handler, like a tapped push's; without one the system opens them.
* Example: a Show in-app button with a trigger name field, marked as a coach-mark target.

## 2.1.1 (unreleased)

* Wraps the PushPilot Android and iOS SDKs 2.1.1, which show live activities started by push with no Dart code: Android draws them as ongoing notifications (promoted Live Updates on Android 16), iOS 17.2+ as Live Activities through a Widget Extension.
* `init(sdkKey, appGroup: ...)`: the App Group shared with the iOS Widget Extension, for images in live activity layouts. Ignored on Android.
* `handleLiveActivityURL(url)`: records a tap on an iOS live activity and returns the activity's own link, or `null` when it has none. Other URLs, and every URL on Android, come back unchanged.

## 2.0.0

* First release on pub.dev, under the Apache License 2.0.
* Wraps the PushPilot Android and iOS SDKs 2.0.0.
* Android: shows PushPilot pushes itself, also when the app is killed, through a receiver for FCM's broadcast; no Dart code runs. `handleMessage` now only tells PushPilot pushes apart in your own handlers.
* iOS: the plugin registers for the APNs device token, passes it to the SDK and forwards taps; `setPushToken` is ignored on iOS. The Firebase token path of 1.x is removed.
* New `setLinkHandler` and `setTapHandler` (Android and iOS) to receive a tapped push's link and custom data in Dart, including for the tap that launched the app, once each.
* Android: the native SDK now starts itself from the key it saved at `init`; the plugin no longer stores the key.
* Optional Notification Service Extension for images and buttons on iOS; steps in the README.

## 1.0.0

* First version: wraps the PushPilot Android and iOS SDKs 1.0.0.
