# PushPilot Flutter plugin

Registers your app's installation with PushPilot, shows PushPilot pushes and records taps on them, so you can send pushes to individual users from the PushPilot dashboard.

- Android and iOS. Needs Flutter 3.47 or later and Dart 3.13 or later (built and tested with Flutter 3.47.1, Dart 3.13.1).
- Android 7.0 (API 24) and later, the minimum for current Flutter (the native SDK itself supports API 23). iOS 15 and later.
- A thin layer over the native PushPilot SDKs 2.3.0 ([Android](https://github.com/pushpilotai/pushpilot-android), [iOS](https://github.com/pushpilotai/pushpilot-ios)). Syncing, retries, storage, validation and showing notifications all happen there.
- No Firebase dependency. On Android your app keeps its own Firebase setup and hands PushPilot the FCM push address; on iOS the plugin uses APNs directly and needs no Firebase at all.
- Never asks for notification permission. No call ever throws; problems are logged in debug builds.

## Install

```yaml
dependencies:
  pushpilot_flutter: ^2.3.0
```

## Integrate

1. **Create the app in PushPilot** (dashboard › Apps) and copy its public SDK key.
2. **Initialise PushPilot at launch.** Calls made before `init` are queued and applied once it runs.

   ```dart
   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await PushPilot.setLinkHandler(router.open); // optional; before init (see Taps and links)
     await PushPilot.setTapHandler((tap) => router.openOrder(tap.data['order_id'])); // optional
     await PushPilot.init('pp_sdk_...');
     runApp(const MyApp());
   }
   ```

3. **Ask for notification permission yourself**, when it suits your app (Android 13+ `POST_NOTIFICATIONS`; iOS `requestAuthorization`). PushPilot never prompts; it reads the result and reports it.
4. **Identify the user** after login with `PushPilot.setExternalUserId(user.id)` and call `PushPilot.logout()` at logout.
5. Do the platform steps below.

### Taps and links

Tapping a PushPilot push records the click and opens its link, or just the app when it has none; a button with a link opens that link, and one without only dismisses the push. Both handlers are optional and work the same on Android and iOS:

- `setLinkHandler(handler)`: the link of a tapped push or button goes to `handler` instead of the system. Without one, the system opens it: a web page in the browser, or a deep link / universal link / URL scheme in your app.
- `setTapHandler(handler)`: each tap that opens the app reaches `handler` as a `TappedNotification` with the push's `notificationId` and its custom `data` (the key-value pairs set on the dashboard).

Set them before `init`. A tap that launches a killed app happens before any Dart runs, so the plugin holds its link and tap until `init` and then delivers each exactly once. Neither is delivered for a dismissal or a button without a link, which do not open the app. When a push's link is a web page and you set no link handler, the browser opens and your app does not, so `setTapHandler` gets nothing for that tap.

On Android, the native link handler must be in place before the launching tap is handled, which is before Flutter starts. The plugin therefore remembers whether your Dart code set a link handler and sets the native one at the next process start. The first launch after you add `setLinkHandler` to an app (or remove it) still follows the previous run's choice for a tap that launches the app; every later tap follows the current one.

### Android: what you add

**The push address.** Set up Firebase Messaging as [FlutterFire documents](https://firebase.flutter.dev/docs/messaging/overview) (`firebase_core`, `firebase_messaging`, `google-services.json`) and forward the address now and whenever it changes. With `firebase_messaging` 17 or later, call `register()` and pass the Firebase Installation ID (FID) that `onRegistered` reports:

```dart
if (defaultTargetPlatform == TargetPlatform.android) {
  await Firebase.initializeApp();
  FirebaseMessaging.instance.onRegistered.listen(PushPilot.setPushToken);
  await FirebaseMessaging.instance.register();
}
```

`register()` needs Firebase's installation ID mode, which also turns off `getToken`. In `android/app/src/main/AndroidManifest.xml` inside `<application>`:

```xml
<meta-data android:name="firebase_messaging_installation_id_enabled" android:value="true" />
```

On older `firebase_messaging` versions, pass the registration token instead: `PushPilot.setPushToken(await FirebaseMessaging.instance.getToken())` plus `onTokenRefresh.listen(PushPilot.setPushToken)`. Pass one or the other, never both: PushPilot keeps a single push address per installation, and the server tells an FID from a token by its shape. Firebase's "installation ID" is not PushPilot's installation id, which the SDK creates and stores itself. An app that gets its FCM address from native code instead of `firebase_messaging` passes it the same way.

**Nothing else is required.** The plugin shows PushPilot pushes itself, also when the app is killed (see [How PushPilot pushes reach the Android SDK](#how-pushpilot-pushes-reach-the-android-sdk)). Taps work as described in [Taps and links](#taps-and-links). Optional, inside `<application>`:

```xml
<!-- Small icon (monochrome; Android draws it as a white silhouette) and the channel name in Settings. -->
<meta-data android:name="ai.pushpilot.sdk.notification_icon" android:resource="@drawable/ic_notification" />
<meta-data android:name="ai.pushpilot.sdk.notification_channel_name" android:value="@string/notifications_channel" />
```

Without them the SDK uses Firebase's `com.google.firebase.messaging.default_notification_icon` if you set one, else your app icon, and the channel name "Notifications".

**Your own Firebase handlers still receive PushPilot pushes** (Android hands every FCM message to every receiver). Skip them, in `onMessage` and the same way in your `onBackgroundMessage` handler:

```dart
FirebaseMessaging.onMessage.listen((message) {
  if (PushPilot.handleMessage(message.data)) return; // already shown by PushPilot
  // Your own pushes, as before.
});
```

Do not also pass PushPilot pushes to the native SDK's `handleMessage` from a `FirebaseMessagingService` of your own: they would be shown twice.

### How PushPilot pushes reach the Android SDK

The plugin's manifest adds a broadcast receiver for FCM's `com.google.android.c2dm.intent.RECEIVE` broadcast, protected by `com.google.android.c2dm.permission.SEND` so that only Google Play services can send it. Android delivers that broadcast to every receiver an app declares for it, so this receiver gets each FCM message next to Firebase's own receiver. It ignores everything without `source` = `pushpilot` and hands PushPilot pushes to the native `PushPilot.handleMessage`, which shows the notification. No Dart code runs, so it works when the app is killed, in the background and in the foreground. The native SDK starts itself from the key and base URL it saved at your last `init`, so delivery and taps are recorded even when Flutter never starts. A small content provider in the plugin runs at process start only to set the native link handler (see [Taps and links](#taps-and-links)).

Why this way: a `FirebaseMessagingService` can't be used, because Android gives the messaging intent to only one service per app, and `firebase_messaging` already declares one. A Dart handler can't be used either, because a killed app has no Dart running, and `onBackgroundMessage` belongs to the app. The receiver works the same whether the app uses `firebase_messaging`, native Firebase Messaging, or another FCM plugin. It is the pattern `firebase_messaging` itself uses for its background messages.

Limits:

- The broadcast is FCM's internal transport, not a documented Firebase API. Firebase has delivered messages this way for years and FlutterFire depends on it, but a future Firebase change could break it; the plugin would then need a new release.
- The receiver has about 10 seconds (Android's limit for a broadcast) to show the push, including downloading its image. A slow image download ends without the image.
- High-priority FCM messages wake a killed app; normal-priority ones may wait for Doze, as for any FCM app. A user who force-stops the app from Settings gets no pushes until they open it again (Android stops all its receivers).

### iOS: what you add

The plugin registers for remote notifications once permission is granted, hands the APNs device token to the SDK and forwards taps; you write no token or tap code, and need no Firebase. You add:

1. **The Push Notifications capability** on the Runner target: *Signing & Capabilities › + Capability › Push Notifications*. This adds the `aps-environment` entitlement.
2. **One line in `AppDelegate`, only if another plugin takes the notification centre.** The plugin makes your `FlutterAppDelegate` the notification centre's delegate when nothing else is, and Flutter then passes taps to every plugin. `firebase_messaging` installs its own delegate unless one is already set, which would hide taps from PushPilot. If your app uses `firebase_messaging` (or any plugin or code that sets `UNUserNotificationCenter.current().delegate`), set it first:

   ```swift
   override func application(_ application: UIApplication,
                             didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
     UNUserNotificationCenter.current().delegate = self // so every plugin, PushPilot too, gets taps
     return super.application(application, didFinishLaunchingWithOptions: launchOptions)
   }
   ```

   Also add `import UserNotifications` at the top. `firebase_messaging` keeps working: it sees a Flutter delegate and gets its calls through it.
3. **Optional: images and buttons**, with a Notification Service Extension (below). Without it, PushPilot pushes show their title and text only.

`setPushToken` does nothing on iOS. Taps work as described in [Taps and links](#taps-and-links); the plugin also reads the tap that launched the app from the scene connection (Flutter passes it to plugins once the engine is attached), so that tap is handled even when the plugin registers after iOS has delivered it to the app delegate. A PushPilot push that arrives while the app is in the foreground shows no banner, as in the native SDK.

### iOS: adding the Notification Service Extension

iOS shows an image in a push only when an app extension attaches it, and shows buttons only for a category registered on the device. Flutter can't add an extension target for you, so add it in Xcode (`ios/Runner.xcworkspace`):

1. **File › New › Target… › Notification Service Extension.** Name it `NotificationService`, language Swift, and choose **Don't Activate** when Xcode asks about the scheme. Its bundle id must start with the app's, for example `com.you.app.NotificationService`.
2. In the new target's **General** tab, set **Minimum Deployments** to iOS 15.0 or later.
3. **Add the `PushPilotNotificationService` library** to the extension target: *General › Frameworks and Libraries › +*, then *Add Other… › Add Package Dependency…* with the pushpilot-ios repository URL (for local development, *Add Local…* and choose the `pushpilot-ios` checkout), and pick `PushPilotNotificationService` (not `PushPilot`) for the `NotificationService` target only.
4. **Replace the generated `NotificationService.swift`** with:

   ```swift
   import PushPilotNotificationService
   import UserNotifications

   final class NotificationService: UNNotificationServiceExtension {
       private let pushPilot = PushPilotServiceExtension()

       override func didReceive(_ request: UNNotificationRequest,
                                withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
           if pushPilot.didReceive(request, withContentHandler: contentHandler) { return }
           contentHandler(request.content) // not a PushPilot push: handle it yourself, or deliver it as is
       }

       override func serviceExtensionTimeWillExpire() {
           pushPilot.serviceExtensionTimeWillExpire()
       }
   }
   ```

5. **Give the extension the app's version**, which App Store Connect requires to match: in the extension's *Build Settings* set **Marketing Version** to `$(FLUTTER_BUILD_NAME)` and **Current Project Version** to `$(FLUTTER_BUILD_NUMBER)`, and make those variables available by giving the extension a base configuration file (*Project › Info › Configurations*, the `NotificationService` row) that contains `#include "../Flutter/Generated.xcconfig"`. Keep **Generate Info.plist File** on (Xcode's default), so the bundle id and version are written into the extension's Info.plist.
6. **Move the embed phase:** in the Runner target's *Build Phases*, drag **Embed Foundation Extensions** above **Thin Binary**. Otherwise the build fails with a "Cycle inside Runner" error.
7. Set the extension's signing team, then build with `flutter build ios` or `flutter run` as usual.

The extension needs no Push Notifications capability and no App Group, and sends nothing to PushPilot; it only downloads the image and registers the button category. `example/ios` has a working extension built this way (`example/ios/NotificationService/`).

### Live activities

From 2.1.1, PushPilot can start, update and end live activities by push, from the dashboard, a campaign or the server API: a score, a delivery or an upload that stays on screen and changes with each update. The native SDKs do all the work; your app starts none itself and needs no Dart beyond the two optional calls below.

**Android: nothing to add.** The Android SDK 2.1.1 draws each live activity as one ongoing notification on a "Live updates" channel, from the same receiver that shows your other PushPilot pushes. On Android 16 an activity sent as promoted shows as a Live Update (status chip, segmented progress) when the user allows it; the SDK's manifest merges the `POST_PROMOTED_NOTIFICATIONS` permission it needs, a normal permission granted at install. Taps open the activity's link like a push's, through `setLinkHandler` when one is set. See the [Android SDK README](https://github.com/pushpilotai/pushpilot-android#live-activities).

**iOS: a Widget Extension.** Live activities started by push need iOS 17.2 or later; the app itself still runs on iOS 15. In Xcode (`ios/Runner.xcworkspace`):

1. **File › New › Target… › Widget Extension**, named for example `LiveActivity`, with the template's *Include …* options unticked, and **Don't Activate** for the scheme. Its bundle id must start with the app's. Set its **Minimum Deployments** to iOS 16.1 or later, and delete the generated widget files except the bundle.
2. **Add the `PushPilotLive` library to the extension target only.** With Swift Package Manager (Flutter's default): *General › Frameworks and Libraries › +*, then the pushpilot-ios package (already in the project if you added the Notification Service Extension; otherwise *Add Other… › Add Package Dependency…* with the pushpilot-ios repository URL) and `PushPilotLive`. With CocoaPods: add the extension's target to `ios/Podfile`, then `pod install`:

   ```ruby
   target 'LiveActivity' do
     pod 'PushPilotLive'
   end
   ```

   The Runner target needs nothing: the plugin brings in `PushPilot`, which includes `PushPilotLive`.
3. **Make the bundle return PushPilot's widget**, which draws every PushPilot layout on the Lock Screen and in the Dynamic Island:

   ```swift
   import PushPilotLive
   import SwiftUI
   import WidgetKit

   @main
   struct LiveActivityWidgets: WidgetBundle {
     var body: some Widget {
       PushPilotLiveActivityWidget(appGroup: "group.com.example.app")
     }
   }
   ```

   To draw activities your own way, return an `ActivityConfiguration(for: PushPilotLiveAttributes.self)` instead; see the [iOS SDK README](https://github.com/pushpilotai/pushpilot-ios#live-activities).
4. **Give the extension the app's version** and move the embed phase, as in steps 5 and 6 of the Notification Service Extension below (base configuration file with `#include "../Flutter/Generated.xcconfig"`; **Embed Foundation Extensions** above **Thin Binary**).
5. **Add `NSSupportsLiveActivities`** (Boolean, `YES`) to `ios/Runner/Info.plist`. Without it iOS starts none, and the SDK tells PushPilot so.
6. **Optional: an App Group** for images in layouts. Add the *App Groups* capability with the same group to Runner and the extension, pass it to the widget as above and to `init`:

   ```dart
   await PushPilot.init('pp_sdk_...', appGroup: 'group.com.example.app');
   ```

   The SDK then downloads the layout's https images into the group for the widget. Without one, image blocks show their fallback icon.
7. **Pass opened URLs to `handleLiveActivityURL`.** A tap on a live activity opens your app with the activity's link plus a `pushpilot_live` marker. `handleLiveActivityURL` counts the click once and returns your link without the marker, or `null` when the activity has none. With Flutter's deep linking (on by default), opened URLs reach a `WidgetsBindingObserver`:

   ```dart
   class OpenedLinks with WidgetsBindingObserver {
     @override
     Future<bool> didPushRouteInformation(RouteInformation info) async {
       final link = await PushPilot.handleLiveActivityURL(info.uri.toString());
       if (link != null) router.open(link); // null: the tap only opens the app
       return true;
     }
   }

   WidgetsBinding.instance.addObserver(OpenedLinks()); // in main(), before runApp
   ```

   A router package or a links plugin works the same way: pass it each URL first. Other URLs come back unchanged, so you can pass every URL through it. On Android it returns every URL unchanged.

The SDK watches PushPilot activities while the app runs and reports their tokens and state to PushPilot. `example/ios/LiveActivity/` is a working extension built this way.

### In-app messages

From 2.2.0 the native SDKs show in-app messages made on the dashboard: a modal, full screen, bottom sheet, top banner, slide-up card, carousel or a coach mark pointing at one of your widgets. Each is an HTML page drawn in a transparent, locked-down web view over your app. The native SDKs fetch, cache, pick and show them, and report `shown`, `clicked` and `dismissed`; the plugin only passes calls through. Details: [Android SDK](https://github.com/pushpilotai/pushpilot-android#in-app-messages), [iOS SDK](https://github.com/pushpilotai/pushpilot-ios#in-app-messages).

1. **Nothing to add for app-open messages.** With `init` called as above, the SDK fetches the messages this installation may see when the app comes to the foreground (at most once a minute, after the installation's first sync), downloads each page with its images and fonts, and shows the first eligible "app open" message on a later foreground. A message shows only from the cache, never from the network.
2. **Named moments.** For a message whose trigger is an in-app call, call `showInApp` with its name where it should appear:

   ```dart
   onPressed: () async {
     final shown = await PushPilot.showInApp('checkout'); // true: a message is now on screen
     // ...your own checkout code
   },
   ```

   The plugin runs it on the platform's main thread, as the native SDKs require. It answers `false` when no cached message is eligible, another message is on screen, the message is past its cap per device or outside its dates, or the SDK has not started. It never throws.
3. **Coach marks.** Wrap the widget a coach mark points at in `PushPilotMark`, with the name the message's target uses in the dashboard:

   ```dart
   PushPilotMark(
     name: 'compose',
     child: FloatingActionButton(onPressed: compose, child: const Icon(Icons.edit)),
   )
   ```

   A Flutter widget has no native view of its own, so after each frame the mark sends its rect to the plugin when it moved or resized. The plugin keeps a transparent native view at that rect inside the Flutter view (in the `FlutterView` on Android, the `FlutterViewController`'s view on iOS) that draws nothing and takes no touches or accessibility focus, and names it with the native `markView`. The mark is removed while its route is covered by another route and when the widget is disposed (`unmarkView`). A later mark with the same name replaces an earlier one. The native rules then apply: the coach mark shows only while the view is on screen (on iOS wholly, on Android at least partly); otherwise the message waits.
4. **Links.** A message's button opens its link through the native SDK: the message closes and the link goes to your `setLinkHandler` handler, exactly like a tapped push's link, so you route it in Dart. Without a handler the system opens it. `javascript:`, `data:`, `file:` and `blob:` links are refused.

Limits of the coach-mark stand-in:

- It follows the widget frame by frame, so while a coach mark is on screen and the user scrolls or animates the widget, the stand-in moves but the open message keeps pointing at the place it opened at (the native SDKs read the target once, when the message shows).
- The rect ignores clipping and what is drawn over the widget: a widget scrolled under an app bar or covered by an overlay in the same route still counts as on screen.
- Only the first Flutter view is used: on Android the first `FlutterView` in the activity, on iOS the registrar's view controller. Apps with several Flutter views (add-to-app) get marks placed in that one only.
- On Android, after a configuration change (rotation) the stand-in moves to the new `FlutterView` with the next rect the mark sends; a widget that ends up at exactly the same rect stays unmarked until it moves.

On Android, the native SDK learns which activity is in the foreground from the moment it is initialised, and Dart's `init` runs after Flutter's activity has already resumed. So after a cold start, app-open messages and `showInApp` wait until the app next comes to the foreground (or another activity resumes). iOS reads the foreground state at `init` and has no such delay.

### Custom events

Record what users do with `track`, then target or report on it in the dashboard:

```dart
PushPilot.track('order_placed', {'value': 49.99, 'currency': 'INR', 'items': 3});
```

Names are snake_case, at most 40 characters, and are registered on first use (up to 100 per app, 20 properties each). Property values are `String`, `num` or `bool`; a numeric `value` is summed in rollups. Pass dates as RFC 3339 strings: a `DateTime` cannot cross the platform channel, and the whole call is dropped. The native SDKs validate events, keep them on the device and send them in batches with retries.

### Moving from 1.x

- Android: remove any code that showed PushPilot pushes yourself; the plugin now shows them. Keep `setPushToken`. Read tapped-push data with `setTapHandler`, not from your activity's intent extras: the native SDK no longer puts it there under your own keys.
- iOS: remove `firebase_messaging`'s token forwarding for PushPilot and the `FirebaseMessagingInstallationIdEnabled` key if you only had it for PushPilot. The 1.x iOS path (Firebase token to PushPilot) is gone: `setPushToken` is ignored on iOS, and the plugin passes the APNs device token itself. Add the Push Notifications capability and, if you use `firebase_messaging`, the `AppDelegate` line above.

## API

All methods are static on `PushPilot`. Each returns a `Future` that completes once the native SDK has the call; you don't need to await it, and it never completes with an error.

| Method | What it does |
|---|---|
| `init(String sdkKey, {String? baseUrl, String? appGroup})` | Starts the SDK. Call once at launch; later calls are ignored. `baseUrl` defaults to `https://pushpilot.ai` and only needs setting for a self-hosted server. `appGroup` (iOS) is the App Group shared with your Widget Extension, for images in [live activities](#live-activities); Android ignores it. |
| `setPushToken(String? token)` | Android only: stores the device's FCM push address and syncs it: the Firebase Installation ID from `onRegistered` (`firebase_messaging` 17+) or the registration token from `getToken` / `onTokenRefresh` (older versions). Pass only one of them. `null` clears it, and the device then stops receiving pushes. Ignored on iOS, where the plugin passes the APNs device token itself. |
| `setExternalUserId(String? id)` | Links this installation to your own user id (1 to 255 characters). One user can have many installations. `null` clears it, the same as `logout()`. |
| `setAttributes(Map<String, Object?> attributes)` | Merges custom attributes. Values are `String`, `num` or `bool`, or `null` to remove one. Pass dates as RFC 3339 strings (`DateTime.toUtc().toIso8601String()`): a `DateTime` cannot cross the platform channel, and the whole call is dropped. Only attributes declared on the dashboard are stored. |
| `track(String name, [Map<String, Object?> properties = const {}])` | Records a [custom event](#custom-events) such as `order_placed`. Names are snake_case, at most 40 characters; property values are `String`, `num` or `bool` (others are dropped), and a numeric `value` is summed in rollups. |
| `setTopics(List<String> topics)` | Replaces the topic list (at most 100; letters, digits and `-_.~%`). Invalid names are dropped. |
| `logout()` | Clears the external user id. The device stays registered and keeps receiving pushes. |
| `forget()` | Deletes this installation from PushPilot and clears everything the SDK stored. A new installation is registered only after your next setter call or the next app launch. To keep a user forgotten, stop calling the SDK for them. |
| `handleMessage(Map<String, dynamic> data) → bool` | Returns `true` when a push came from PushPilot (its data has `source` = `pushpilot`). Use it to skip PushPilot pushes in your own Firebase handlers; the plugin already shows them. Answered in Dart, so it works in a background isolate and needs no `init`. |
| `setLinkHandler(void Function(String url)? handler)` | Sends the link of a tapped PushPilot push or button to `handler` instead of letting the system open it. `null` lets the system open links again. Set it before `init` to also get the link of the tap that launched the app; each link arrives once. |
| `handleLiveActivityURL(String url) → Future<String?>` | For a URL your app was opened with: a tap on an iOS live activity is counted once and returns the activity's own link without PushPilot's marker, or `null` when it has none. Any other URL, and every URL on Android, comes back unchanged. Never throws. See [Live activities](#live-activities). |
| `showInApp(String name) → Future<bool>` | Shows the first eligible cached [in-app message](#in-app-messages) whose trigger is `name`, on the platform's main thread; `true` when one is now on screen. Never throws. |
| `PushPilotMark({required String name, required Widget child})` | A widget, not a method: names `child` as the coach-mark target `name`. See [In-app messages](#in-app-messages). |
| `setTapHandler(void Function(TappedNotification tap)? handler)` | Sends each tap that opened the app to `handler`, with `tap.notificationId` and `tap.data` (the push's custom data, `Map<String, String>`). `null` stops them. Set it before `init` to also get the tap that launched the app; each tap arrives once. |

Invalid values are dropped by the native SDK with a log message instead of being sent.

## What is sent, and store declarations

The plugin sends nothing itself. What the native SDKs send and when, and what to declare in the Google Play **Data safety** form and App Store Connect **App Privacy**, are in the native READMEs:

- Android: [What the SDK sends, and when](https://github.com/pushpilotai/pushpilot-android#what-the-sdk-sends-and-when) and [Google Play Data safety form](https://github.com/pushpilotai/pushpilot-android#google-play-data-safety-form)
- iOS: [What the SDK sends, and when](https://github.com/pushpilotai/pushpilot-ios#what-the-sdk-sends-and-when) and [App Store Connect: App Privacy](https://github.com/pushpilotai/pushpilot-ios#app-store-connect-app-privacy)

The iOS SDK ships its own privacy manifest, which Xcode merges into your app's privacy report.

## Local development

The plugin and its example use the published native SDKs: `ai.pushpilot:sdk` from Maven Central and `https://github.com/pushpilotai/pushpilot-ios` from its tags. To work against unreleased changes in the native SDKs, check them out beside this repository:

```
pushpilot-sdks/
  pushpilot-android/
  pushpilot-ios/
  pushpilot-flutter/
```

and switch these places locally (don't commit them):

**Android.** The plugin depends on `ai.pushpilot:sdk:2.3.0` (`android/build.gradle.kts`). Publish your working copy to your local Maven repository and add `mavenLocal()` to the app's repositories (for the example, in `allprojects { repositories { ... } }` of `example/android/build.gradle.kts`):

```bash
cd ../pushpilot-android && ./gradlew :sdk:publishToMavenLocal
```

**iOS with Swift Package Manager** (Flutter's default). In `ios/pushpilot_flutter/Package.swift`, replace the `pushPilot` line with a local path. Flutter reaches this manifest through a symlink, so resolve the path from the real file:

```swift
let pushPilot = Package.Dependency.package(path: URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
    .deletingLastPathComponent().appendingPathComponent("../../../pushpilot-ios").standardized.path)
```

The example's Notification Service and Live Activity extensions share one `pushpilot-ios` package reference in `example/ios/Runner.xcodeproj`: in Xcode, replace it under *Package Dependencies* with *Add Local…* and the checkout.

**iOS with CocoaPods** (apps with Swift Package Manager turned off, for example `enable-swift-package-manager: false` under `flutter: config:` in the app's `pubspec.yaml`). The plugin's podspec depends on the `PushPilot` pod, which `PushPilot.podspec` in the `pushpilot-ios` checkout provides. It contains the `PushPilot` library and depends on the `PushPilotLive` pod (`PushPilotLive.podspec`; add `pod 'PushPilotLive', :path => '<path to pushpilot-ios>'` to the Widget Extension's target too). Add `PushPilotNotificationService` to your extension as a Swift package (step 3 of the extension steps), which works in a CocoaPods app too. Until the pods are on CocoaPods trunk, and to build a local checkout, add this to the app's `ios/Podfile`, inside `target 'Runner'` after `flutter_install_all_ios_pods`:

```ruby
pod 'PushPilot', :path => '<path to pushpilot-ios>'
```

Only add it to a CocoaPods build: with Swift Package Manager on, the plugin already gets PushPilot as a Swift package, and the pod would link it twice. The example uses Swift Package Manager, so it has no Podfile; to try CocoaPods with it, turn the setting off, run `flutter build ios --config-only` once to generate `example/ios/Podfile` (its `pod install` fails until the line is added), and add the line with the path `../../../pushpilot-ios`. Once the pod is on CocoaPods trunk, the Podfile line is only needed for a local checkout.

The full release order is in [RELEASING.md](RELEASING.md).

## Example app

`example/` sets a link handler and a tap handler and initialises PushPilot at launch, shows the last tapped link and tap, and has buttons for permission, set user id, set topics, logout and forget. On Android it forwards the Firebase Installation ID from `firebase_messaging` `register()` / `onRegistered` and skips PushPilot pushes in its own `onMessage` handler. On iOS it has the Push Notifications entitlement, the `AppDelegate` line, and a Notification Service Extension (`example/ios/NotificationService/`). For live activities it passes the App Group `group.ai.pushpilot.pushpilotFlutterExample` to `init` and every opened URL through `handleLiveActivityURL` (the screen shows the link that comes back), and on iOS it has `NSSupportsLiveActivities`, the App Group on both targets, and a `LiveActivity` Widget Extension (`example/ios/LiveActivity/`) linking `PushPilotLive` from the pushpilot-ios package. For in-app messages it has a trigger name field and a **Show in-app message** button that calls `showInApp` and shows the answer; the button is wrapped in `PushPilotMark(name: 'example_show_in_app')`, so a coach mark aimed at that name points at it. It builds and runs without a Firebase config; Android then has no push address, while iOS needs no Firebase. To try it with real pushes:

1. Android: put your `google-services.json` in `example/android/app/` (the Google services Gradle plugin is applied only when the file exists), with an application id registered in your Firebase project. It is git-ignored; never commit it.
2. iOS: set your signing team, bundle ids and an App Group you own for all three targets (the extensions' bundle ids must start with the app's), and add your APNs key to the PushPilot app.
3. Run on a device with your SDK key:

   ```bash
   cd example && flutter run --dart-define=PUSHPILOT_SDK_KEY=pp_sdk_...
   ```

   Add `--dart-define=PUSHPILOT_BASE_URL=https://your-server` for a self-hosted server.

4. Tap **Allow notifications**, then send a test push from the dashboard's device lookup.

On the iOS simulator the app gets a device token once you allow notifications, and `xcrun simctl push` shows a PushPilot payload, but it does not run the extension, so images and buttons need a real push.

## Tests

```bash
flutter analyze && flutter test
```

The Dart tests mock the platform channel and check that every call sends the right method and arguments, and that links and taps from native reach the handlers. The native glue that holds taps and links until `init` and passes each tap once is tested on both platforms: Android with `cd example/android && ./gradlew :pushpilot_flutter:testDebugUnitTest`, iOS (also `setPushToken` being refused) in `example/ios/RunnerTests`. `handleLiveActivityURL` is tested on both, the iOS side against the real SDK's link parsing. For in-app messages, the Dart tests check `showInApp`'s answers and the rects `PushPilotMark` sends (after layout, on a move, on dispose, under a covering route); `example/ios/RunnerTests` checks the iOS stand-in views and `showInApp` through the channel:

```bash
cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RunnerTests
```

## Licence

Apache License 2.0. See [LICENSE](LICENSE).
