import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// PushPilot SDK for Flutter. Every call goes straight to the native PushPilot SDK, which does
/// all syncing, retrying, storage and validation. No call ever throws.
class PushPilot {
  PushPilot._();

  static const MethodChannel _channel = MethodChannel('ai.pushpilot/sdk');
  static void Function(String url)? _linkHandler;
  static void Function(TappedNotification tap)? _tapHandler;

  /// Starts the SDK with the app's public SDK key. Call once at launch; later calls are ignored.
  /// [baseUrl] is only needed for a self-hosted server. [appGroup] (iOS) is the App Group shared with your
  /// Widget Extension, so images in live activity layouts can be shown; pass the same id to
  /// `PushPilotLiveActivityWidget(appGroup:)`. Android ignores it.
  static Future<void> init(String sdkKey, {String? baseUrl, String? appGroup}) => _call('init', {
        'sdkKey': sdkKey,
        'baseUrl': baseUrl,
        'appGroup': ?appGroup,
      });

  /// Pass every URL your app is opened with. For a tap on an iOS live activity it records the click once
  /// and returns the activity's own link without PushPilot's marker, or null when the activity has none
  /// (just show the app). Any other URL, and every URL on Android, comes back unchanged. Never throws: on a
  /// failure it returns [url] as given.
  static Future<String?> handleLiveActivityURL(String url) async {
    try {
      return await _channel.invokeMethod<String>('handleLiveActivityURL', url);
    } catch (e) {
      if (kDebugMode) debugPrint('PushPilot.handleLiveActivityURL failed: $e');
      return url;
    }
  }

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

  /// Shows the first eligible cached in-app message whose trigger is [name], on the platform's main thread,
  /// and returns whether one is now on screen. False when none is cached and eligible, another message is
  /// showing, the SDK has not started, or the call failed. No network call; never throws. Links the message
  /// opens go to [setLinkHandler]'s handler, like a tapped push's.
  static Future<bool> showInApp(String name) async {
    try {
      return await _channel.invokeMethod<bool>('showInApp', name) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('PushPilot.showInApp failed: $e');
      return false;
    }
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

/// Names [child] for coach-mark in-app messages whose target is [name], the Flutter form of the native
/// `markView`. After each frame it sends the child's rect to the plugin, which keeps a transparent native
/// view at that spot for the SDK to point at; it unmarks while its route is covered and when it is removed.
/// A later mark with the same name replaces an earlier one.
class PushPilotMark extends StatefulWidget {
  /// Marks [child] as [name].
  const PushPilotMark({super.key, required this.name, required this.child});

  /// The coach-mark target name the dashboard's message asks for.
  final String name;

  /// The widget the coach mark points at.
  final Widget child;

  /// Creates the state that reports the child's rect.
  @override
  State<PushPilotMark> createState() => _PushPilotMarkState();
}

class _PushPilotMarkState extends State<PushPilotMark> {
  // The mark that last placed each name, so an old mark going away leaves a newer one in place.
  static final _owners = <String, _PushPilotMarkState>{};
  Rect? _sent;
  bool _routeIsCurrent = true;

  /// Reports the rect once the first frame is laid out.
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback(_report);
  }

  /// A new name: removes the old one; the next frame places the new one.
  @override
  void didUpdateWidget(PushPilotMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) _unmark(oldWidget.name);
  }

  /// Removes the native mark with the widget.
  @override
  void dispose() {
    _unmark(widget.name);
    super.dispose();
  }

  /// After each frame: sends the child's global rect when it moved or resized, or unmarks while it has no
  /// size or its route is covered. Frames only run while something changes, so an idle screen costs nothing.
  void _report(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final rect = _routeIsCurrent && box != null && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    if (rect != _sent) {
      if (rect == null) {
        _unmark(widget.name);
      } else {
        _owners[widget.name] = this;
        PushPilot._call('markView',
            {'name': widget.name, 'x': rect.left, 'y': rect.top, 'width': rect.width, 'height': rect.height});
        _sent = rect;
      }
    }
    SchedulerBinding.instance.addPostFrameCallback(_report);
  }

  /// Tells the plugin to drop [name], unless a newer mark has taken it.
  void _unmark(String name) {
    _sent = null;
    if (_owners[name] != this) return;
    _owners.remove(name);
    PushPilot._call('unmarkView', name);
  }

  /// Returns the child; also notes whether its route is the top one (a covered screen is not a target).
  @override
  Widget build(BuildContext context) {
    _routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    return widget.child;
  }
}
