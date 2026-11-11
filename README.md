# PushPilot Flutter plugin

Registers your app's installation with PushPilot and forwards its FCM push token, so you can send pushes to individual users from the PushPilot dashboard.

- Android and iOS. Needs Flutter 3.47 or later and Dart 3.13 or later (built and tested with Flutter 3.47.1, Dart 3.13.1).
- Android 7.0 (API 24) and later, the minimum for current Flutter (the native SDK itself supports API 23). iOS 15 and later.
- A thin layer over the native PushPilot SDKs ([Android](../pushpilot-android/README.md), [iOS](../pushpilot-ios/README.md)). Syncing, retries, storage and validation all happen there; the Dart calls only pass through.
- No Firebase dependency: your app keeps its own Firebase setup (`firebase_messaging`) and hands PushPilot the token.
- Never asks for notification permission. No call ever throws; problems are logged in debug builds.

## Install

```yaml
dependencies:
  pushpilot_flutter: ^1.0.0
```

The plugin and the native SDKs are not published yet. Until they are, see [Local development](#local-development).

## Integrate

1. **Set up Firebase Messaging** in your app as [FlutterFire documents](https://firebase.flutter.dev/docs/messaging/overview): `firebase_core` and `firebase_messaging`, your `google-services.json` and `GoogleService-Info.plist`, the iOS *Push Notifications* capability, and your APNs key uploaded to the Firebase console.
2. **Create the app in PushPilot** (dashboard › Apps) and copy its public SDK key.
3. **Initialise PushPilot at launch and forward the FCM token**, now and on every refresh. `init` does not touch Firebase, so it can run before or after `Firebase.initializeApp()`. Calls made before `init` are queued and applied once it runs.

   ```dart
   import 'package:firebase_core/firebase_core.dart';
   import 'package:firebase_messaging/firebase_messaging.dart';
   import 'package:pushpilot_flutter/pushpilot_flutter.dart';

   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     PushPilot.init('pp_sdk_...');
     await Firebase.initializeApp();
     FirebaseMessaging.instance.onTokenRefresh.listen(PushPilot.setPushToken);
     PushPilot.setPushToken(await FirebaseMessaging.instance.getToken());
     runApp(const MyApp());
   }
   ```

   Pass the FCM **registration token** from `getToken` / `onTokenRefresh`. `firebase_messaging` 17 marks these deprecated in favour of `register` / `onRegistered`, but those yield a Firebase Installation ID, which PushPilot cannot send to.

4. **Tell PushPilot pushes apart** from your others, here in the foreground and the same way in your `onBackgroundMessage` handler:

   ```dart
   FirebaseMessaging.onMessage.listen((message) {
     if (PushPilot.handleMessage(message.data)) {
       // A PushPilot push. Show it or route it as you like.
     }
   });
   ```

5. **Ask for notification permission yourself**, when it suits your app, for example with `FirebaseMessaging.instance.requestPermission()`. PushPilot never prompts; it reads the result and reports it.
6. **Identify the user** after login with `PushPilot.setExternalUserId(user.id)` and call `PushPilot.logout()` at logout.

## API

All methods are static on `PushPilot`. Each returns a `Future` that completes once the native SDK has the call; you don't need to await it, and it never completes with an error.

| Method | What it does |
|---|---|
| `init(String sdkKey, {String? baseUrl})` | Starts the SDK. Call once at launch; later calls are ignored. `baseUrl` defaults to `https://pushpilot.ai` and only needs setting for a self-hosted server. |
| `setPushToken(String? token)` | Stores the FCM token and syncs it. `null` clears it, and the device then stops receiving pushes. |
| `setExternalUserId(String? id)` | Links this installation to your own user id (1 to 255 characters). One user can have many installations. `null` clears it, the same as `logout()`. |
| `setAttributes(Map<String, Object?> attributes)` | Merges custom attributes. Values are `String`, `num` or `bool`, or `null` to remove one. Pass dates as RFC 3339 strings (`DateTime.toUtc().toIso8601String()`): a `DateTime` cannot cross the platform channel, and the whole call is dropped. Only attributes declared on the dashboard are stored. |
| `setTopics(List<String> topics)` | Replaces the topic list (at most 100; letters, digits and `-_.~%`). Invalid names are dropped. |
| `logout()` | Clears the external user id. The device stays registered and keeps receiving pushes. |
| `forget()` | Deletes this installation from PushPilot and clears everything the SDK stored. A new installation is registered only after your next setter call or the next app launch. To keep a user forgotten, stop calling the SDK for them. |
| `handleMessage(Map<String, dynamic> data) → bool` | Returns `true` when a push came from PushPilot (its data has `source` = `pushpilot`). Answered in Dart, so it works in a background isolate and needs no `init`. |

Invalid values are dropped by the native SDK with a log message instead of being sent.

## What is sent, and store declarations

The plugin sends nothing itself. What the native SDKs send and when, and what to declare in the Google Play **Data safety** form and App Store Connect **App Privacy**, are in the native READMEs:

- Android: [What the SDK sends, and when](../pushpilot-android/README.md#what-the-sdk-sends-and-when) and [Google Play Data safety form](../pushpilot-android/README.md#google-play-data-safety-form)
- iOS: [What the SDK sends, and when](../pushpilot-ios/README.md#what-the-sdk-sends-and-when) and [App Store Connect: App Privacy](../pushpilot-ios/README.md#app-store-connect-app-privacy)

The iOS SDK ships its own privacy manifest, which Xcode merges into your app's privacy report.

## Local development

The native SDKs are not published, so the plugin builds them from sibling checkouts next to this repository: `../pushpilot-android` and `../pushpilot-ios`. Each switch to the published artifact is one marked spot.

**Android.** The plugin depends on `ai.pushpilot:sdk:1.0.0` (`android/build.gradle.kts`). Publish it to your local Maven repository and add `mavenLocal()` to the app's repositories (the example does this in `example/android/build.gradle.kts`):

```bash
cd ../pushpilot-android && ./gradlew :sdk:publishToMavenLocal
```

At release: publish the SDK to Maven Central and delete the `mavenLocal()` line.

**iOS with Swift Package Manager** (Flutter's default). `ios/pushpilot_flutter/Package.swift` depends on `../pushpilot-ios` by local path, so it builds your working copy. At release: replace the marked `pushPilot` line with `.package(url: "<pushpilot-ios repository URL>", from: "1.0.0")`.

**iOS with CocoaPods** (apps with Swift Package Manager turned off, for example `enable-swift-package-manager: false` under `flutter: config:` in the app's `pubspec.yaml`). The native SDK has no podspec, so the plugin's podspec depends on a pod named `PushPilot`, and `ios/dev/PushPilot.podspec` provides it, built from the committed state of the `pushpilot-ios` checkout. Add this to the app's `ios/Podfile`, inside `target 'Runner'` after `flutter_install_all_ios_pods`:

```ruby
pod 'PushPilot', :podspec => '<path to this repo>/ios/dev/PushPilot.podspec'
```

Only add it to a CocoaPods build: with Swift Package Manager on, the plugin already gets PushPilot as a Swift package, and the pod would link it twice. The example uses Swift Package Manager, so it has no Podfile; to try CocoaPods with it, turn the setting off, run `flutter build ios --config-only` once to generate `example/ios/Podfile` (its `pod install` fails until the line is added), and add the line with the path `../../ios/dev/PushPilot.podspec`. Run `pod update PushPilot` after committing changes in `pushpilot-ios`. At release: move `ios/dev/PushPilot.podspec` into the pushpilot-ios repository with its public `:git` URL and a `:tag`, publish it to CocoaPods trunk, then delete `ios/dev/` and the Podfile line.

When everything is published, also remove `publish_to: none` from `pubspec.yaml`.

## Example app

`example/` initialises PushPilot at launch, forwards the token from `firebase_messaging`, and has buttons for permission, set user id, set topics, logout and forget. It builds and runs without a Firebase config, and then has no push token. To try it with real pushes:

1. Put your `google-services.json` in `example/android/app/` (the Google services Gradle plugin is applied only when the file exists) and add your `GoogleService-Info.plist` to the `Runner` target in Xcode. Both are git-ignored; never commit them.
2. Use a bundle id and application id registered in your Firebase project, and set your signing team in Xcode.
3. Run on a device with your SDK key:

   ```bash
   cd example && flutter run --dart-define=PUSHPILOT_SDK_KEY=pp_sdk_...
   ```

   Add `--dart-define=PUSHPILOT_BASE_URL=https://your-server` for a self-hosted server.

4. Tap **Allow notifications**, then send a test push from the dashboard's device lookup.

## Tests

```bash
flutter analyze && flutter test
```

The tests mock the platform channel and check that every call sends the right method and arguments.

## Licence

No licence has been chosen yet.
