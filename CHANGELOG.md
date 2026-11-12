## 2.0.0

* Wraps the PushPilot Android and iOS SDKs 2.0.0.
* Android: shows PushPilot pushes itself, also when the app is killed, through a receiver for FCM's broadcast; no Dart code runs. `handleMessage` now only tells PushPilot pushes apart in your own handlers.
* iOS: the plugin registers for the APNs device token, passes it to the SDK and forwards taps; `setPushToken` is ignored on iOS. The Firebase token path of 1.x is removed.
* New `setLinkHandler` (iOS) to receive the link of a tapped push in Dart.
* Optional Notification Service Extension for images and buttons on iOS; steps in the README.

## 1.0.0

* First version: wraps the PushPilot Android and iOS SDKs 1.0.0.
