import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:pushpilot_flutter/pushpilot_flutter.dart';

// Pass your own with --dart-define=PUSHPILOT_SDK_KEY=pp_sdk_... (and PUSHPILOT_BASE_URL for a self-hosted server).
const sdkKey = String.fromEnvironment('PUSHPILOT_SDK_KEY', defaultValue: 'pp_sdk_replace_me');
const baseUrl = String.fromEnvironment('PUSHPILOT_BASE_URL');

/// Starts PushPilot first, then the UI, then Firebase token forwarding.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushPilot.init(sdkKey, baseUrl: baseUrl.isEmpty ? null : baseUrl);
  runApp(const ExampleApp());
  await forwardPushToken();
}

/// Hands PushPilot the FCM token now and on every refresh, and spots PushPilot pushes.
/// Without google-services.json / GoogleService-Info.plist Firebase cannot start, so the app runs without a token.
Future<void> forwardPushToken() async {
  try {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    // PushPilot sends to FCM registration tokens. firebase_messaging 17 deprecates getToken/onTokenRefresh in
    // favour of register/onRegistered, which yield a Firebase Installation ID instead, so keep the token APIs.
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen(PushPilot.setPushToken);
    FirebaseMessaging.onMessage.listen((message) {
      if (PushPilot.handleMessage(message.data)) debugPrint('PushPilot push: ${message.notification?.title}');
    });
    // ignore: deprecated_member_use
    await PushPilot.setPushToken(await messaging.getToken());
  } catch (e) {
    debugPrint('No push token (Firebase not configured or token unavailable): $e');
  }
}

/// One screen of buttons, one per PushPilot call the app makes after launch.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  /// Lays out the buttons.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('PushPilot example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // PushPilot never prompts; the app asks when it suits it.
            button('Allow notifications', () => FirebaseMessaging.instance.requestPermission()),
            button('Set user id', () => PushPilot.setExternalUserId('user-123')),
            button('Set topics', () => PushPilot.setTopics(['news', 'offers'])),
            button('Log out', PushPilot.logout),
            button('Forget this device', PushPilot.forget),
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
