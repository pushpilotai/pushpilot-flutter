import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// PushPilot SDK for Flutter. Every call goes straight to the native PushPilot SDK, which does
/// all syncing, retrying, storage and validation. No call ever throws.
class PushPilot {
  PushPilot._();

  static const MethodChannel _channel = MethodChannel('ai.pushpilot/sdk');

  /// Starts the SDK with the app's public SDK key. Call once at launch; later calls are ignored.
  /// [baseUrl] is only needed for a self-hosted server.
  static Future<void> init(String sdkKey, {String? baseUrl}) =>
      _call('init', {'sdkKey': sdkKey, 'baseUrl': baseUrl});

  /// Passes the FCM token at launch and on every refresh; null clears it.
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

  /// True when a received push came from PushPilot. Pass `RemoteMessage.data`; makes no call.
  static bool handleMessage(Map<String, dynamic> data) => data['source'] == 'pushpilot';

  /// Sends one call to the native SDK and swallows any failure so the app never sees it.
  static Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e) {
      if (kDebugMode) debugPrint('PushPilot.$method failed: $e');
    }
  }
}
