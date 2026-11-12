import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pushpilot_flutter/pushpilot_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ai.pushpilot/sdk');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  // Runs one call and checks the single method call it sent.
  Future<void> expectCall(Future<void> Function() run, String method, Object? arguments) async {
    await run();
    expect(calls, hasLength(1));
    expect(calls.single.method, method);
    expect(calls.single.arguments, arguments);
  }

  test('init sends the key and base URL', () async {
    await expectCall(() => PushPilot.init('pp_sdk_1', baseUrl: 'https://example.test'), 'init',
        {'sdkKey': 'pp_sdk_1', 'baseUrl': 'https://example.test'});
  });

  test('init without a base URL sends null', () async {
    await expectCall(() => PushPilot.init('pp_sdk_1'), 'init', {'sdkKey': 'pp_sdk_1', 'baseUrl': null});
  });

  test('setPushToken sends the token or null', () async {
    await expectCall(() => PushPilot.setPushToken('tok'), 'setPushToken', 'tok');
    calls.clear();
    await expectCall(() => PushPilot.setPushToken(null), 'setPushToken', null);
  });

  test('setPushToken passes a Firebase Installation ID through unchanged', () async {
    const fid = 'cR3kXq9-Tz_1aB2cD3eF4g'; // 22 base64url characters, the shape of an FID
    expect(fid, hasLength(22));
    await expectCall(() => PushPilot.setPushToken(fid), 'setPushToken', fid);
  });

  test('setExternalUserId sends the id or null', () async {
    await expectCall(() => PushPilot.setExternalUserId('u1'), 'setExternalUserId', 'u1');
    calls.clear();
    await expectCall(() => PushPilot.setExternalUserId(null), 'setExternalUserId', null);
  });

  test('setAttributes sends the map as given', () async {
    final attributes = {'plan': 'pro', 'seats': 3, 'ratio': 0.5, 'trial': true, 'old': null};
    await expectCall(() => PushPilot.setAttributes(attributes), 'setAttributes', attributes);
  });

  test('setTopics sends the list', () async {
    await expectCall(() => PushPilot.setTopics(['news', 'deals']), 'setTopics', ['news', 'deals']);
  });

  test('logout and forget send no arguments', () async {
    await expectCall(PushPilot.logout, 'logout', null);
    calls.clear();
    await expectCall(PushPilot.forget, 'forget', null);
  });

  test('setLinkHandler tells native whether Dart handles links', () async {
    await expectCall(() => PushPilot.setLinkHandler((_) {}), 'setLinkHandler', true);
    calls.clear();
    await expectCall(() => PushPilot.setLinkHandler(null), 'setLinkHandler', false);
  });

  test('a link from native reaches the handler', () async {
    final links = <String>[];
    await PushPilot.setLinkHandler(links.add);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onLink', 'myapp://orders/42')),
      (_) {},
    );
    expect(links, ['myapp://orders/42']);
    await PushPilot.setLinkHandler(null);
  });

  test('setTapHandler tells native whether Dart handles taps', () async {
    await expectCall(() => PushPilot.setTapHandler((_) {}), 'setTapHandler', true);
    calls.clear();
    await expectCall(() => PushPilot.setTapHandler(null), 'setTapHandler', false);
  });

  test('a tap from native reaches the handler with its data', () async {
    final taps = <TappedNotification>[];
    await PushPilot.setTapHandler(taps.add);
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onTap', {
        'notificationId': 'n-42',
        'data': {'order_id': '42'},
      })),
      (_) {},
    );
    expect(taps.single.notificationId, 'n-42');
    expect(taps.single.data, {'order_id': '42'});
    await PushPilot.setTapHandler(null);
  });

  test('handleMessage answers in Dart without a channel call', () {
    expect(PushPilot.handleMessage({'source': 'pushpilot', 'k': 'v'}), isTrue);
    expect(PushPilot.handleMessage({'source': 'other'}), isFalse);
    expect(PushPilot.handleMessage({}), isFalse);
    expect(calls, isEmpty);
  });

  test('native errors and a missing plugin never throw', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'x'));
    await PushPilot.setTopics(['a']);
    messenger.setMockMethodCallHandler(channel, null);
    await PushPilot.logout();
    // A value the codec cannot encode fails inside the call too.
    await PushPilot.setAttributes({'when': DateTime(2026)});
  });
}
