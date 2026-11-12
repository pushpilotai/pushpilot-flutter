# PushPilot Flutter plugin

Registers your app's installation with PushPilot, shows PushPilot pushes and records taps on them, so you can send pushes to individual users from the PushPilot dashboard.

- Android and iOS. Needs Flutter 3.47 or later and Dart 3.13 or later (built and tested with Flutter 3.47.1, Dart 3.13.1).
- Android 7.0 (API 24) and later, the minimum for current Flutter (the native SDK itself supports API 23). iOS 15 and later.
- A thin layer over the native PushPilot SDKs 2.0.0 ([Android](../pushpilot-android/README.md), [iOS](../pushpilot-ios/README.md)). Syncing, retries, storage, validation and showing notifications all happen there.
- No Firebase dependency. On Android your app keeps its own Firebase setup and hands PushPilot the FCM push address; on iOS the plugin uses APNs directly and needs no Firebase at all.
- Never asks for notification permission. No call ever throws; problems are logged in debug builds.

## Install

```yaml
dependencies:
  pushpilot_flutter: ^2.0.0
```

The plugin and the native SDKs are not published yet. Until they are, see [Local development](#local-development).

## Integrate

1. **Create the app in PushPilot** (dashboard › Apps) and copy its public SDK key.
2. **Initialise PushPilot at launch.** Calls made before `init` are queued and applied once it runs.

   ```dart
   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     await PushPilot.setLinkHandler(router.open); // optional, iOS only; before init (see below)
     await PushPilot.init('pp_sdk_...');
     runApp(const MyApp());
   }
   ```

3. **Ask for notification permission yourself**, when it suits your app (Android 13+ `POST_NOTIFICATIONS`; iOS `requestAuthorization`). PushPilot never prompts; it reads the result and reports it.
4. **Identify the user** after login with `PushPilot.setExternalUserId(user.id)` and call `PushPilot.logout()` at logout.
5. Do the platform steps below.

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

**Nothing else is required.** The plugin shows PushPilot pushes itself, also when the app is killed (see [How PushPilot pushes reach the Android SDK](#how-pushpilot-pushes-reach-the-android-sdk)). Tapping one opens its link, or your launcher activity when it has none. Optional, inside `<application>`:

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

The plugin's manifest adds a broadcast receiver for FCM's `com.google.android.c2dm.intent.RECEIVE` broadcast, protected by `com.google.android.c2dm.permission.SEND` so that only Google Play services can send it. Android delivers that broadcast to every receiver an app declares for it, so this receiver gets each FCM message next to Firebase's own receiver. It ignores everything without `source` = `pushpilot` and hands PushPilot pushes to the native `PushPilot.handleMessage`, which shows the notification. No Dart code runs, so it works when the app is killed, in the background and in the foreground. A small content provider starts the native SDK with the key and base URL of your last `init` when the process starts, so delivery and taps are recorded even when Flutter never starts.

Why this way: a `FirebaseMessagingService` can't be used, because Android gives the messaging intent to only one service per app, and `firebase_messaging` already declares one. A Dart handler can't be used either, because a killed app has no Dart running, and `onBackgroundMessage` belongs to the app. The receiver works the same whether the app uses `firebase_messaging`, native Firebase Messaging, or another FCM plugin. It is the pattern `firebase_messaging` itself uses for its background messages.

Limits:

- The broadcast is FCM's internal transport, not a documented Firebase API. Firebase has delivered messages this way for years and FlutterFire depends on it, but a future Firebase change could break it; the plugin would then need a new release.
- The receiver has about 10 seconds (Android's limit for a broadcast) to show the push, including downloading its image. A slow image download ends without the image.
- High-priority FCM messages wake a killed app; normal-priority ones may wait for Doze, as for any FCM app. A user who force-stops the app from Settings gets no pushes until they open it again (Android stops all its receivers).
- The content provider starts the native SDK early in every process start, including those caused by an FCM message, so the SDK may sync then too, as it does in a native app that calls `init` in `Application.onCreate`.
- No link handler on Android, and the push's custom `data` is not passed to Dart when a push is tapped: the native Android SDK opens links through Android itself (deep links or the browser) and gives no way to tell its launch-intent extras from others.

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

`setPushToken` does nothing on iOS. Tapping a push records the click and opens its link through iOS (Safari, a universal link or your URL scheme), or, if you set `PushPilot.setLinkHandler`, sends the link to your Dart handler instead. Set the handler before `init` to also receive the link of a tap that launched the app. A PushPilot push that arrives while the app is in the foreground shows no banner, as in the native SDK.

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

### Moving from 1.x

- Android: remove any code that showed PushPilot pushes yourself; the plugin now shows them. Keep `setPushToken`.
- iOS: remove `firebase_messaging`'s token forwarding for PushPilot and the `FirebaseMessagingInstallationIdEnabled` key if you only had it for PushPilot. The 1.x iOS path (Firebase token to PushPilot) is gone: `setPushToken` is ignored on iOS, and the plugin passes the APNs device token itself. Add the Push Notifications capability and, if you use `firebase_messaging`, the `AppDelegate` line above.

## API

All methods are static on `PushPilot`. Each returns a `Future` that completes once the native SDK has the call; you don't need to await it, and it never completes with an error.

| Method | What it does |
|---|---|
| `init(String sdkKey, {String? baseUrl})` | Starts the SDK. Call once at launch; later calls are ignored. `baseUrl` defaults to `https://pushpilot.ai` and only needs setting for a self-hosted server. |
| `setPushToken(String? token)` | Android only: stores the device's FCM push address and syncs it: the Firebase Installation ID from `onRegistered` (`firebase_messaging` 17+) or the registration token from `getToken` / `onTokenRefresh` (older versions). Pass only one of them. `null` clears it, and the device then stops receiving pushes. Ignored on iOS, where the plugin passes the APNs device token itself. |
| `setExternalUserId(String? id)` | Links this installation to your own user id (1 to 255 characters). One user can have many installations. `null` clears it, the same as `logout()`. |
| `setAttributes(Map<String, Object?> attributes)` | Merges custom attributes. Values are `String`, `num` or `bool`, or `null` to remove one. Pass dates as RFC 3339 strings (`DateTime.toUtc().toIso8601String()`): a `DateTime` cannot cross the platform channel, and the whole call is dropped. Only attributes declared on the dashboard are stored. |
| `setTopics(List<String> topics)` | Replaces the topic list (at most 100; letters, digits and `-_.~%`). Invalid names are dropped. |
| `logout()` | Clears the external user id. The device stays registered and keeps receiving pushes. |
| `forget()` | Deletes this installation from PushPilot and clears everything the SDK stored. A new installation is registered only after your next setter call or the next app launch. To keep a user forgotten, stop calling the SDK for them. |
| `handleMessage(Map<String, dynamic> data) → bool` | Returns `true` when a push came from PushPilot (its data has `source` = `pushpilot`). Use it to skip PushPilot pushes in your own Firebase handlers; the plugin already shows them. Answered in Dart, so it works in a background isolate and needs no `init`. |
| `setLinkHandler(void Function(String url)? handler)` | iOS only: sends the link of a tapped PushPilot push or button to `handler` instead of letting iOS open it. `null` lets iOS open links again. Set it before `init` to also get the link of a tap that launched the app. Does nothing on Android. |

Invalid values are dropped by the native SDK with a log message instead of being sent.

## What is sent, and store declarations

The plugin sends nothing itself. What the native SDKs send and when, and what to declare in the Google Play **Data safety** form and App Store Connect **App Privacy**, are in the native READMEs:

- Android: [What the SDK sends, and when](../pushpilot-android/README.md#what-the-sdk-sends-and-when) and [Google Play Data safety form](../pushpilot-android/README.md#google-play-data-safety-form)
- iOS: [What the SDK sends, and when](../pushpilot-ios/README.md#what-the-sdk-sends-and-when) and [App Store Connect: App Privacy](../pushpilot-ios/README.md#app-store-connect-app-privacy)

The iOS SDK ships its own privacy manifest, which Xcode merges into your app's privacy report.

## Local development

The native SDKs are not published, so the plugin builds them from sibling checkouts next to this repository: `../pushpilot-android` and `../pushpilot-ios`. Each switch to the published artifact is one marked spot.

**Android.** The plugin depends on `ai.pushpilot:sdk:2.0.0` (`android/build.gradle.kts`). Publish it to your local Maven repository and add `mavenLocal()` to the app's repositories (the example does this in `example/android/build.gradle.kts`):

```bash
cd ../pushpilot-android && git switch feat/sdk-v2 && ./gradlew :sdk:publishToMavenLocal
```

At release: publish the SDK to Maven Central and delete the `mavenLocal()` line.

**iOS with Swift Package Manager** (Flutter's default). `ios/pushpilot_flutter/Package.swift` depends on `../pushpilot-ios` by local path, so it builds your working copy. At release: replace the marked `pushPilot` line with `.package(url: "<pushpilot-ios repository URL>", from: "2.0.0")`. The example's Notification Service Extension also uses the local checkout (`../../../pushpilot-ios` in `example/ios/Runner.xcodeproj`); switch it to the repository URL the same way.

**iOS with CocoaPods** (apps with Swift Package Manager turned off, for example `enable-swift-package-manager: false` under `flutter: config:` in the app's `pubspec.yaml`). The native SDK has no podspec, so the plugin's podspec depends on a pod named `PushPilot`, and `ios/dev/PushPilot.podspec` provides it, built from the latest commit on the `feat/sdk-v2` branch of the `pushpilot-ios` checkout. It contains only the `PushPilot` library; add `PushPilotNotificationService` to your extension as a Swift package (step 3 of the extension steps), which works in a CocoaPods app too. Add this to the app's `ios/Podfile`, inside `target 'Runner'` after `flutter_install_all_ios_pods`:

```ruby
pod 'PushPilot', :podspec => '<path to this repo>/ios/dev/PushPilot.podspec'
```

Only add it to a CocoaPods build: with Swift Package Manager on, the plugin already gets PushPilot as a Swift package, and the pod would link it twice. The example uses Swift Package Manager, so it has no Podfile; to try CocoaPods with it, turn the setting off, run `flutter build ios --config-only` once to generate `example/ios/Podfile` (its `pod install` fails until the line is added), and add the line with the path `../../ios/dev/PushPilot.podspec`. Run `pod update PushPilot` after new commits on that branch. At release: move `ios/dev/PushPilot.podspec` into the pushpilot-ios repository with its public `:git` URL and a `:tag`, publish it to CocoaPods trunk, then delete `ios/dev/` and the Podfile line.

When everything is published, also remove `publish_to: none` from `pubspec.yaml`.

## Example app

`example/` sets a link handler and initialises PushPilot at launch, shows the last tapped link, and has buttons for permission, set user id, set topics, logout and forget. On Android it forwards the Firebase Installation ID from `firebase_messaging` `register()` / `onRegistered` and skips PushPilot pushes in its own `onMessage` handler. On iOS it has the Push Notifications entitlement, the `AppDelegate` line, and a Notification Service Extension (`example/ios/NotificationService/`). It builds and runs without a Firebase config; Android then has no push address, while iOS needs no Firebase. To try it with real pushes:

1. Android: put your `google-services.json` in `example/android/app/` (the Google services Gradle plugin is applied only when the file exists), with an application id registered in your Firebase project. It is git-ignored; never commit it.
2. iOS: set your signing team and bundle ids you own for both targets (the extension's must start with the app's), and add your APNs key to the PushPilot app.
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

The Dart tests mock the platform channel and check that every call sends the right method and arguments, and that links from native reach the handler. The iOS glue (where a tapped link goes before and after `init`, and `setPushToken` being refused) is tested in `example/ios/RunnerTests`:

```bash
cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RunnerTests
```

## Licence

No licence has been chosen yet.
