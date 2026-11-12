import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PushPilot SDK for Flutter. Every call goes straight to the native PushPilot SDK, which does
/// all syncing, retrying, storage and validation. No call ever throws.
class PushPilot {
  PushPilot._();

  static const MethodChannel _channel = MethodChannel('ai.pushpilot/sdk');
  static void Function(String url)? _linkHandler;
  static void Function(TappedNotification tap)? _tapHandler;

  /// Starts the SDK with the app's public SDK key. Call once at launch; later calls are ignored.
  /// [baseUrl] is only needed for a self-hosted server.
  static Future<void> init(String sdkKey, {String? baseUrl}) =>
      _call('init', {'sdkKey': sdkKey, 'baseUrl': baseUrl});

  /// Android only: passes the device's FCM push address; null clears it. With firebase_messaging 17 or later
  /// that is the Firebase Installation ID from `onRegistered` after `register()`; on older versions it is the
  /// token from `getToken` and `onTokenRefresh`. Pass only one of the two. (Firebase's installation ID is not
  /// PushPilot's own installation id.) On iOS the plugin passes the APNs device token itself and this call
  /// is ignored.
  static Future<void> setPushToken(String? token) => _call('setPushToken', token);

  /// Links this installation to the app's own user id after login; null clears it.
  static Future<void> setExternalUserId(String? id) => _call('setExternalUserId', id);

  /// Merges attributes declared in the dashboard. Values are String, num, bool, or null to remove.
  static Future<void> setAttributes(Map<String, Object?> attributes) =>
      _call('setAttributes', attributes);

  /// Replaces this installation's topic list.
  static Future<void> setTopics(List<String> topics) => _call('setTopics', topics);

  /// Clears the external user id; the device stays registered and keeps receiving pushes.
  static Future<void> logout() => _call('logout');

  /// Deletes this installation from PushPilot and clears local state.
  static Future<void> forget() => _call('forget');

  /// True when a received push came from PushPilot. Pass `RemoteMessage.data`; makes no call. The plugin
  /// already shows PushPilot pushes itself, so use this in your own Firebase handlers to skip them.
  static bool handleMessage(Map<String, dynamic> data) => data['source'] == 'pushpilot';

  /// Sends the link of a tapped PushPilot push or button to [handler] instead of letting the system open
  /// it; null lets the system open links again. Set it before [init] to also get the link of the tap that
  /// launched the app; links wait until [init] and arrive once each.
  static Future<void> setLinkHandler(void Function(String url)? handler) {
    _linkHandler = handler;
    _channel.setMethodCallHandler(_onNativeCall);
    return _call('setLinkHandler', handler != null);
  }

  /// Sends each tap on a PushPilot push that opened the app, with the push's custom data, to [handler];
  /// null stops them. Set it before [init] to also get the tap that launched the app; taps wait until
  /// [init] and arrive once each.
  static Future<void> setTapHandler(void Function(TappedNotification tap)? handler) {
    _tapHandler = handler;
    _channel.setMethodCallHandler(_onNativeCall);
    return _call('setTapHandler', handler != null);
  }

  /// Receives the native side's calls: a tapped link or a tap, for the handlers.
  static Future<void> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onLink':
        _linkHandler?.call(call.arguments as String);
      case 'onTap':
        final args = call.arguments as Map;
        _tapHandler?.call(TappedNotification(
            args['notificationId'] as String, Map<String, String>.from(args['data'] as Map)));
    }
  }

  /// Sends one call to the native SDK and swallows any failure so the app never sees it.
  static Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e) {
      if (kDebugMode) debugPrint('PushPilot.$method failed: $e');
    }
  }
}

/// A tapped PushPilot push that opened the app.
class TappedNotification {
  /// Creates one; the plugin does this for each tap.
  const TappedNotification(this.notificationId, this.data);

  /// PushPilot's id for the notification, the same one its events carry.
  final String notificationId;

  /// The push's custom data from the dashboard; empty when it had none.
  final Map<String, String> data;
}
