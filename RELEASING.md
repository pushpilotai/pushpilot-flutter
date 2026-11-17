# Releasing the Flutter plugin

A version on pub.dev can never be replaced or deleted. Every step marked **Owner** needs the owner's explicit yes for that version.

Release only after the native SDKs of the same version are public: `ai.pushpilot:sdk` on Maven Central and the `pushpilot-ios` tag on GitHub (plus the `PushPilot` pod on CocoaPods trunk, if CocoaPods is supported).

## One-time setup (owner)

1. Verify `pushpilot.ai` in Google Search Console (DNS TXT record), with the Google account that will publish.
2. At <https://pub.dev/create-publisher> create the verified publisher `pushpilot.ai`.
3. `dart pub login` on the release machine with that account.

## Each release

1. Set the version in `pubspec.yaml`, `ios/pushpilot_flutter.podspec`, the native versions in `android/build.gradle.kts`, `ios/pushpilot_flutter/Package.swift` and the podspec's `PushPilot` dependency, the install snippet in `README.md`, and add a `## <version>` section to `CHANGELOG.md`.
2. Switch from the local native SDKs to the published ones:
   - `ios/pushpilot_flutter/Package.swift`: replace the marked local `pushPilot` line with `.package(url: "https://github.com/pushpilotai/pushpilot-ios", from: "<version>")`.
   - `example/android/build.gradle.kts`: delete the `mavenLocal()` line.
   - `example/ios/Runner.xcodeproj`: switch the extensions' local `pushpilot-ios` package (one reference, shared by NotificationService and LiveActivity) to `https://github.com/pushpilotai/pushpilot-ios`.
   - `pubspec.yaml`: delete the `publish_to: none` line.
   - `README.md`: update *Local development* to say how to point back at local checkouts.
3. Checks pass:

   ```bash
   flutter analyze && flutter test
   cd example/android && ./gradlew :pushpilot_flutter:testDebugUnitTest && cd ../..
   cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RunnerTests && cd ../..
   flutter pub publish --dry-run
   ```

   Read the file list the dry run prints: no `google-services.json`, `GoogleService-Info.plist`, keys, `local.properties` or build output.
4. Rehearse with the example app on Android and iOS: register against a local PushPilot server, receive a push with an image and buttons, tap it and see the click counted.
5. Commit, merge to `main`, tag `<version>`. **Owner:** push `main` and the tag to `github.com/pushpilotai/pushpilot-flutter`.
6. **Owner:** `flutter pub publish` and confirm. On the first release, then open the package's *Admin* tab on pub.dev and transfer it to the `pushpilot.ai` publisher.
7. Verify: a fresh `flutter create` app adds `pushpilot_flutter: ^<version>` from pub.dev and the push check passes on both platforms.
