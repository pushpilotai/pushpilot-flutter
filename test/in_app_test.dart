import 'package:flutter/material.dart';
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

  // The markView and unmarkView calls sent so far, as short strings.
  List<String> marks() => [
        for (final call in calls)
          if (call.method == 'markView')
            'mark ${(call.arguments as Map).values.join(' ')}'
          else if (call.method == 'unmarkView')
            'unmark ${call.arguments}',
      ];

  // A screen with one 100x40 mark at (left, top).
  Widget screen({double left = 10, double top = 20, String name = 'compose', bool marked = true}) => MaterialApp(
        home: Stack(children: [
          Positioned(
            left: left,
            top: top,
            child: marked
                ? PushPilotMark(name: name, child: const SizedBox(width: 100, height: 40))
                : const SizedBox(width: 100, height: 40),
          ),
        ]),
      );

  test('showInApp sends the name and returns what native answers', () async {
    reply = (_) => true;
    expect(await PushPilot.showInApp('checkout'), isTrue);
    expect(calls.single.method, 'showInApp');
    expect(calls.single.arguments, 'checkout');
    reply = (_) => false;
    expect(await PushPilot.showInApp('checkout'), isFalse);
  });

  test('showInApp is false on a null answer, an error or a missing plugin', () async {
    expect(await PushPilot.showInApp('x'), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'x'));
    expect(await PushPilot.showInApp('x'), isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await PushPilot.showInApp('x'), isFalse);
  });

  testWidgets('a mark sends its global rect after layout, then only when it changes', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(marks(), ['mark compose 10.0 20.0 100.0 40.0']);
    await tester.pump();
    expect(marks(), hasLength(1));
    await tester.pumpWidget(screen(left: 30, top: 50));
    await tester.pump();
    expect(marks().last, 'mark compose 30.0 50.0 100.0 40.0');
    expect(marks(), hasLength(2));
  });

  testWidgets('a mark is removed with the widget', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pumpWidget(screen(marked: false));
    await tester.pump();
    expect(marks(), ['mark compose 10.0 20.0 100.0 40.0', 'unmark compose']);
  });

  testWidgets('a renamed mark removes the old name and places the new one', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.pumpWidget(screen(name: 'search'));
    await tester.pump();
    expect(marks(), [
      'mark compose 10.0 20.0 100.0 40.0',
      'unmark compose',
      'mark search 10.0 20.0 100.0 40.0',
    ]);
  });

  testWidgets('a mark under a pushed route is removed, and placed again when the route pops', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Align(
        alignment: Alignment.topLeft,
        child: PushPilotMark(name: 'compose', child: SizedBox(width: 100, height: 40)),
      ),
    ));
    await tester.pump();
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await tester.pumpAndSettle();
    expect(marks(), ['mark compose 0.0 0.0 100.0 40.0', 'unmark compose']);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(marks().last, 'mark compose 0.0 0.0 100.0 40.0');
  });

  testWidgets('an older mark going away leaves a newer mark with the same name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(children: const [
        PushPilotMark(key: ValueKey('a'), name: 'compose', child: SizedBox(width: 10, height: 10)),
        PushPilotMark(key: ValueKey('b'), name: 'compose', child: SizedBox(width: 20, height: 20)),
      ]),
    ));
    await tester.pump();
    // Both report in the first frame; the second (20x20) is the last to place the name.
    expect(marks().last, endsWith('20.0 20.0'));
    await tester.pumpWidget(MaterialApp(
      home: Column(children: const [
        PushPilotMark(key: ValueKey('b'), name: 'compose', child: SizedBox(width: 20, height: 20)),
      ]),
    ));
    await tester.pump();
    expect(marks().where((m) => m.startsWith('unmark')), isEmpty);
  });
}
