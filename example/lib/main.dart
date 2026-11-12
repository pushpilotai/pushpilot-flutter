import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pushpilot_flutter/pushpilot_flutter.dart';

// Pass your own with --dart-define=PUSHPILOT_SDK_KEY=pp_sdk_... (and PUSHPILOT_BASE_URL for a self-hosted server).
const sdkKey = String.fromEnvironment('PUSHPILOT_SDK_KEY', defaultValue: 'pp_sdk_replace_me');
const baseUrl = String.fromEnvironment('PUSHPILOT_BASE_URL');

// The example's own permission prompt (MainActivity.kt, AppDelegate.swift); PushPilot never asks.
const permission = MethodChannel('pushpilot_example/permission');

/// The last link a tapped PushPilot push gave the app (iOS), shown on screen.
final lastLink = ValueNotifier<String?>(null);

/// Sets the link handler, starts PushPilot, then the UI; on Android also forwards the FCM address.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before init, so the link of a tap that launched the app arrives here too.
  await PushPilot.setLinkHandler((url) => lastLink.value = url);
  await PushPilot.init(sdkKey, baseUrl: baseUrl.isEmpty ? null : baseUrl);
  runApp(const ExampleApp());
  // iOS needs nothing here: the plugin hands PushPilot the APNs device token itself.
  if (defaultTargetPlatform == TargetPlatform.android) await forwardPushToken();
}

/// Android: registers with FCM and hands PushPilot the Firebase Installation ID, now and whenever it changes.
/// The plugin shows PushPilot pushes itself. Without google-services.json Firebase cannot start, so the app
/// runs without a push address.
Future<void> forwardPushToken() async {
  try {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    messaging.onRegistered.listen(PushPilot.setPushToken);
    FirebaseMessaging.onMessage.listen((message) {
      if (PushPilot.handleMessage(message.data)) return; // already shown by PushPilot
      debugPrint('Another push: ${message.messageId}');
    });
    await messaging.register();
  } catch (e) {
    debugPrint('No push address (Firebase not configured or unavailable): $e');
  }
}

/// One screen of buttons, one per PushPilot call the app makes after launch.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  /// Lays out the buttons and the last tapped link.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('PushPilot example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            button('Allow notifications', () => permission.invokeMethod<void>('request')),
            button('Set user id', () => PushPilot.setExternalUserId('user-123')),
            button('Set topics', () => PushPilot.setTopics(['news', 'offers'])),
            button('Log out', PushPilot.logout),
            button('Forget this device', PushPilot.forget),
            ValueListenableBuilder(
              valueListenable: lastLink,
              builder: (context, link, _) => Text('Last link: ${link ?? 'none'}'),
            ),
          ],
        ),
      ),
    );
  }

  /// A full-width button that runs [action] and ignores its result.
  Widget button(String label, Future<Object?> Function() action) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton(onPressed: () => action().ignore(), child: Text(label)),
      );
}
