import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';
import 'package:night_owl_ub/features/map/providers/venue_story_activity_provider.dart';

final _testSessionProvider = StateProvider<String?>((ref) => 'viewer-a');

List<Map<String, dynamic>> _rows(int count) => [
      {
        'venue_ref': 'osm:node:123',
        'story_count': count,
        'activity_day': '2026-11-03',
        'next_expiry': '2099-11-03T20:00:00Z',
      }
    ];

void main() {
  testWidgets('session switch ignores an older in-flight private count',
      (tester) async {
    final requests = <Completer<dynamic>>[];
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => const Stream.empty()),
      sessionUserIdProvider
          .overrideWith((ref) => ref.watch(_testSessionProvider)),
      venueStoryActivityLoaderProvider.overrideWithValue(() {
        final request = Completer<dynamic>();
        requests.add(request);
        return request.future;
      }),
    ]);
    try {
      container.listen(venueStoryActivityProvider, (_, __) {});
      expect(requests, hasLength(1));
      container.read(_testSessionProvider.notifier).state = 'viewer-b';
      container.read(venueStoryActivityProvider);
      await tester.pump();
      expect(requests, hasLength(2));
      requests[1].complete(_rows(1));
      await tester.pump();
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          1);
      requests[0].complete(_rows(99));
      await tester.pump();
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          1);
    } finally {
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('social changes, minute polling and app resume refresh activity',
      (tester) async {
    var calls = 0;
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => const Stream.empty()),
      sessionUserIdProvider.overrideWithValue('viewer'),
      venueStoryActivityLoaderProvider.overrideWithValue(() async {
        calls++;
        return _rows(calls);
      }),
    ]);
    try {
      container.listen(venueStoryActivityProvider, (_, __) {});
      await tester.pump();
      expect(calls, 1);
      container.read(socialVersionProvider.notifier).state++;
      container.read(venueStoryActivityProvider);
      await tester.pump();
      expect(calls, 2);
      await tester.pump(const Duration(milliseconds: 60100));
      container.read(venueStoryActivityProvider);
      await tester.pump();
      expect(calls, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      container.read(venueStoryActivityProvider);
      expect(calls, 3,
          reason: 'No background polling while the app is paused.');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      container.read(venueStoryActivityProvider);
      await tester.pump();
      expect(calls, 4);
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          4);
    } finally {
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets(
      'network failures stay errors and retry instead of reporting zero',
      (tester) async {
    var calls = 0;
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => const Stream.empty()),
      sessionUserIdProvider.overrideWithValue(null),
      venueStoryActivityLoaderProvider.overrideWithValue(() async {
        calls++;
        if (calls == 1) throw StateError('Offline');
        return <Map<String, dynamic>>[];
      }),
    ]);
    try {
      container.listen(venueStoryActivityProvider, (_, __) {});
      await tester.pump();
      expect(container.read(venueStoryActivityProvider).hasError, isTrue);
      expect(container.read(venueStoryActivityProvider).valueOrNull, isNull);
      await tester.pump(const Duration(minutes: 1));
      container.read(venueStoryActivityProvider);
      await tester.pump();
      expect(calls, 2);
      expect(container.read(venueStoryActivityProvider).valueOrNull, isEmpty);
    } finally {
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
