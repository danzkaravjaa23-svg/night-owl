import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/constants/app_constants.dart';
import 'package:night_owl_ub/core/widgets/policy_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final policy in AppPolicy.values) {
    for (final outcome in ['opened', 'refused', 'exception']) {
      testWidgets('${policy.name} handles $outcome with a usable fallback',
          (tester) async {
        final opened = <Uri>[];
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Builder(builder: (context) {
            return TextButton(
              onPressed: () =>
                  openAppPolicy(context, policy, open: (uri) async {
                opened.add(uri);
                if (outcome == 'exception') {
                  throw StateError('fixture-private-browser-failure');
                }
                return outcome == 'opened';
              }),
              child: const Text('Open policy'),
            );
          })),
        ));
        await tester.tap(find.text('Open policy'));
        await tester.pumpAndSettle();
        expect(opened, [policy.uri]);
        expect(policy.uri.toString(),
            '${AppConstants.publicAppUrl.replaceFirst(RegExp(r'/+$'), '')}/${policy.file}');
        if (outcome == 'opened') {
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text(policy.title), findsOneWidget);
          final fallback =
              tester.widget<SelectableText>(find.byType(SelectableText));
          expect(fallback.data, contains(policy.uri.toString()));
          expect(fallback.data, contains('osokhe@gmail.com'));
          expect(fallback.data,
              isNot(contains('fixture-private-browser-failure')));
          await tester.tap(find.text('Хаах'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final outcome in ['refused', 'exception']) {
    testWidgets('disposed policy caller ignores a late $outcome response',
        (tester) async {
      final pending = Completer<bool>();
      Future<void>? action;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () {
                        action = openAppPolicy(context, AppPolicy.privacy,
                            open: (_) => pending.future);
                      },
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpWidget(const SizedBox());
      if (outcome == 'exception') {
        pending.completeError(StateError('fixture-private-error'));
      } else {
        pending.complete(false);
      }
      await action;
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('policy buttons wrap at 320px with large text and open both URLs',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final requests = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'launch');
      requests.add((call.arguments as Map)['url'] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: const Scaffold(
          body: Padding(padding: EdgeInsets.all(20), child: PolicyLinks())),
    ));
    for (final policy in [AppPolicy.terms, AppPolicy.privacy]) {
      final button = find.widgetWithText(TextButton, policy.title);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(button).right, lessThanOrEqualTo(320));
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    expect(requests,
        [AppPolicy.terms.uri.toString(), AppPolicy.privacy.uri.toString()]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
