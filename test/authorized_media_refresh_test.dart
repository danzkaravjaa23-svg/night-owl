import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/constants/app_constants.dart';
import 'package:night_owl_ub/core/services/media_access.dart';
import 'package:night_owl_ub/core/widgets/authorized_media.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';

final _account = StateProvider<String?>((_) => 'owner-A');
const _url =
    '${AppConstants.backendUrl}/storage/v1/object/public/posts/owner/media.mp4';

void main() {
  test(
      'legacy public and stored signed URLs normalize the same exact owned object',
      () {
    for (final route in ['public', 'sign', 'authenticated']) {
      final source =
          '${AppConstants.backendUrl}/storage/v1/object/$route/avatars/owner/old%20photo.jpg?token=old&v=123';
      expect(protectedStorageObject(source),
          (bucket: 'avatars', path: 'owner/old photo.jpg'));
      expect(
          sameProtectedMediaObject(
              source, source.replaceFirst('token=old', 'token=new')),
          isTrue);
    }
    expect(
        protectedStorageObject(
            _url.replaceFirst('supabase.co', 'supabase.co.evil.test')),
        isNull);
    expect(
        protectedStorageObject(
            _url.replaceFirst('/media.mp4', '/%2fmedia.mp4')),
        isNull);
    expect(
        sameProtectedMediaObject(
            _url, _url.replaceFirst('media.mp4', 'other.mp4')),
        isFalse);
  });

  Future<ProviderContainer> show(
      WidgetTester tester, Future<String> Function(String) signer,
      {DateTime Function()? clock, bool visible = true}) async {
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(_account)),
      authorizedMediaSignerProvider.overrideWithValue(signer),
      if (clock != null) authorizedMediaClockProvider.overrideWithValue(clock),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: TickerMode(
                enabled: visible,
                child: AuthorizedMedia(
                    url: _url,
                    builder: (source) => Text(source),
                    placeholder: () => const Text('waiting'))))));
    await tester.pump();
    return container;
  }

  testWidgets(
      'renews before expiry while retaining the loaded source until the replacement is ready',
      (tester) async {
    var calls = 0;
    var now = DateTime.utc(2026, 11, 3);
    final renewal = Completer<String>();
    await show(tester,
        (_) => ++calls == 1 ? Future.value('first-source') : renewal.future,
        clock: () => now);
    expect(find.text('first-source'), findsOneWidget);
    now = now.add(const Duration(seconds: 270));
    await tester.pump(const Duration(seconds: 270));
    expect(calls, 2);
    expect(find.text('first-source'), findsOneWidget);
    renewal.complete('renewed-source');
    await tester.pumpAndSettle();
    expect(find.text('renewed-source'), findsOneWidget);
    expect(find.text('waiting'), findsNothing);
  });

  testWidgets(
      'background suspends renewal and foreground refreshes an expired source',
      (tester) async {
    var calls = 0;
    var now = DateTime.utc(2026, 11, 3);
    await show(tester, (_) async => 'source-${++calls}', clock: () => now);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('source-2'), findsOneWidget);
  });

  testWidgets('offstage media does not start a signing clock', (tester) async {
    var calls = 0;
    await show(tester, (_) async => 'source-${++calls}', visible: false);
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 0);
    expect(find.text('waiting'), findsOneWidget);
  });

  testWidgets(
      'late account and privacy responses cannot paint in the new access scope',
      (tester) async {
    final replies = <Completer<String>>[];
    final container = await show(tester, (_) {
      final reply = Completer<String>();
      replies.add(reply);
      return reply.future;
    });
    container.read(_account.notifier).state = 'owner-B';
    await tester.pump();
    expect(replies, hasLength(2));
    replies[0].complete('private-A');
    await tester.pump();
    expect(find.text('private-A'), findsNothing);
    container.read(socialVersionProvider.notifier).state++;
    await tester.pump();
    expect(replies, hasLength(3));
    replies[1].complete('old-privacy-B');
    await tester.pump();
    expect(find.text('old-privacy-B'), findsNothing);
    replies[2].complete('current-B');
    await tester.pumpAndSettle();
    expect(find.text('current-B'), findsOneWidget);
  });

  testWidgets(
      'already loaded private media clears immediately on an account or privacy change',
      (tester) async {
    var calls = 0;
    final replies = <Completer<String>>[];
    final container = await show(tester, (_) {
      if (++calls == 1) return Future.value('visible-A');
      final reply = Completer<String>();
      replies.add(reply);
      return reply.future;
    });
    expect(find.text('visible-A'), findsOneWidget);
    container.read(_account.notifier).state = 'owner-B';
    await tester.pump();
    expect(find.text('visible-A'), findsNothing);
    expect(find.text('waiting'), findsOneWidget);
    replies[0].complete('visible-B');
    await tester.pumpAndSettle();
    expect(find.text('visible-B'), findsOneWidget);
    container.read(socialVersionProvider.notifier).state++;
    await tester.pump();
    expect(find.text('visible-B'), findsNothing);
    expect(find.text('waiting'), findsOneWidget);
    replies[1].complete('new-access-B');
    await tester.pumpAndSettle();
    expect(find.text('new-access-B'), findsOneWidget);
  });

  testWidgets('dispose cancels clocks and ignores a pending signing result',
      (tester) async {
    var calls = 0;
    final reply = Completer<String>();
    await show(tester, (_) {
      calls++;
      return reply.future;
    });
    await tester.pumpWidget(const SizedBox());
    reply.completeError(StateError('late network failure'));
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a hung signer reaches a retry state and does not retry forever offline',
      (tester) async {
    var calls = 0;
    await show(tester, (_) {
      calls++;
      return Completer<String>().future;
    });
    await tester.pump(const Duration(seconds: 13));
    expect(find.byTooltip('Медиа дахин ачаалах'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 13));
    await tester.pump(const Duration(minutes: 10));
    expect(calls, 2);
  });
}
