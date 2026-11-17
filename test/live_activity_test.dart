import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushpilot_flutter/pushpilot_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ai.pushpilot/sdk');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) reply = (_) => null;

  setUp(() {
    calls.clear();
    reply = (_) => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply(call);
    });
  });

  test('init sends the App Group when given', () async {
    await PushPilot.init('pp_sdk_1', baseUrl: 'https://example.test', appGroup: 'group.com.example.app');
    expect(calls.single.method, 'init');
    expect(calls.single.arguments,
        {'sdkKey': 'pp_sdk_1', 'baseUrl': 'https://example.test', 'appGroup': 'group.com.example.app'});
  });

  test('init without an App Group leaves the key out', () async {
    await PushPilot.init('pp_sdk_1');
    expect((calls.single.arguments as Map).containsKey('appGroup'), isFalse);
  });

  test('handleLiveActivityURL sends the URL and returns the native answer, link or null', () async {
    reply = (_) => 'https://example.com/orders/42';
    expect(await PushPilot.handleLiveActivityURL('https://example.com/orders/42?pushpilot_live=abc'),
        'https://example.com/orders/42');
    expect(calls.single.method, 'handleLiveActivityURL');
    expect(calls.single.arguments, 'https://example.com/orders/42?pushpilot_live=abc');

    reply = (_) => null;
    expect(await PushPilot.handleLiveActivityURL('pushpilot-live://open?pushpilot_live=abc'), isNull);
  });

  test('handleLiveActivityURL never throws: a native failure gives the URL back', () async {
    reply = (_) => throw PlatformException(code: 'boom');
    expect(await PushPilot.handleLiveActivityURL('myapp://orders/42'), 'myapp://orders/42');
  });

  test('handleLiveActivityURL gives the URL back when the plugin is missing', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await PushPilot.handleLiveActivityURL('myapp://orders/42'), 'myapp://orders/42');
  });
}
