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

  test('track sends the name and properties', () async {
    final properties = {'value': 49.99, 'currency': 'INR', 'items': 3, 'gift': false};
    await PushPilot.track('order_placed', properties);
    expect(calls.single.method, 'track');
    expect(calls.single.arguments, {'name': 'order_placed', 'properties': properties});
  });

  test('track without properties sends an empty map', () async {
    await PushPilot.track('app_opened');
    expect(calls.single.method, 'track');
    expect(calls.single.arguments, {'name': 'app_opened', 'properties': <String, Object?>{}});
  });

  test('track never throws', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'x'));
    await PushPilot.track('order_placed');
    // A value the codec cannot encode fails inside the call too.
    await PushPilot.track('order_placed', {'when': DateTime(2026)});
  });
}
