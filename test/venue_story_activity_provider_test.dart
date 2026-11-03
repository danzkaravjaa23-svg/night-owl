import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';
import 'package:night_owl_ub/features/map/providers/venue_story_activity_provider.dart';

final _testSessionProvider = StateProvider<String?>((ref) => 'viewer-a');

List<Map<String, dynamic>> _rows(int count,
        {int? postCount, DateTime? nextExpiry}) =>
    [
      {
        'venue_ref': 'osm:node:123',
        'story_count': count,
        if (postCount != null) 'post_count': postCount,
        'activity_day': '2026-11-03',
        'next_expiry':
            nextExpiry?.toUtc().toIso8601String() ?? '2099-11-03T20:00:00Z',
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
      requests[1].complete(_rows(1, postCount: 2));
      await tester.pump();
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          3);
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .postCount,
          2);
      requests[0].complete(_rows(99, postCount: 100));
      await tester.pump();
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          3);
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .postCount,
          2);
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

  testWidgets('post rolling expiry refreshes counts and leaves no stale level',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var calls = 0;
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => const Stream.empty()),
      sessionUserIdProvider.overrideWithValue('viewer'),
      venueStoryActivityLoaderProvider.overrideWithValue(() async {
        calls++;
        return calls == 1
            ? _rows(0,
                postCount: 15,
                nextExpiry: DateTime.now().add(const Duration(seconds: 3)))
            : <Map<String, dynamic>>[];
      }),
    ]);
    try {
      container.listen(venueStoryActivityProvider, (_, __) {});
      await tester.pump();
      final activity = container
          .read(venueStoryActivityProvider)
          .valueOrNull!['osm:node:123']!;
      expect(activity.count, 15);
      expect(activity.storyCount, 0);
      expect(activity.postCount, 15);
      await tester.pump(const Duration(seconds: 4));
      container.read(venueStoryActivityProvider);
      await tester.pump();
      expect(calls, 2);
      expect(container.read(venueStoryActivityProvider).valueOrNull, isEmpty);
    } finally {
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets(
      'relationship reload hides old mixed counts until permissions settle',
      (tester) async {
    final requests = <Completer<dynamic>>[];
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => const Stream.empty()),
      sessionUserIdProvider.overrideWithValue('viewer'),
      venueStoryActivityLoaderProvider.overrideWithValue(() {
        final request = Completer<dynamic>();
        requests.add(request);
        return request.future;
      }),
    ]);
    try {
      container.listen(venueStoryActivityProvider, (_, __) {});
      requests.single.complete(_rows(4, postCount: 11));
      await tester.pump();
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          15);
      container.read(socialVersionProvider.notifier).state++;
      final loading = container.read(venueStoryActivityProvider);
      expect(loading.isLoading, isTrue,
          reason:
              'Consumers suppress previous data during visibility refresh.');
      await tester.pump();
      expect(requests, hasLength(2));
      requests.last.complete(_rows(0, postCount: 1));
      await tester.pump();
      final visible = container
          .read(venueStoryActivityProvider)
          .valueOrNull!['osm:node:123']!;
      expect(visible.count, 1);
      expect(visible.storyCount, 0);
      expect(visible.postCount, 1);
    } finally {
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('malformed supplied post counts stay errors and retry',
      (tester) async {
    var calls = 0;
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => const Stream.empty()),
      sessionUserIdProvider.overrideWithValue('viewer'),
      venueStoryActivityLoaderProvider.overrideWithValue(() async {
        calls++;
        if (calls == 1) {
          return [
            {..._rows(5).single, 'post_count': null}
          ];
        }
        return _rows(1, postCount: 1);
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
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          2);
    } finally {
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('post changes refresh immediately and ignore older mixed counts',
      (tester) async {
    final requests = <Completer<dynamic>>[];
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => const Stream.empty()),
      sessionUserIdProvider.overrideWithValue('viewer'),
      venueStoryActivityLoaderProvider.overrideWithValue(() {
        final request = Completer<dynamic>();
        requests.add(request);
        return request.future;
      }),
    ]);
    try {
      container.listen(venueStoryActivityProvider, (_, __) {});
      requests.single.complete(_rows(4, postCount: 11));
      await tester.pump();
      expect(
          container
              .read(venueStoryActivityProvider)
              .valueOrNull!['osm:node:123']!
              .count,
          15);
      container.read(postsVersionProvider.notifier).state++;
      expect(container.read(venueStoryActivityProvider).isLoading, isTrue);
      await tester.pump();
      expect(requests, hasLength(2));
      container.read(postsVersionProvider.notifier).state++;
      container.read(venueStoryActivityProvider);
      await tester.pump();
      expect(requests, hasLength(3));
      requests[2].complete(_rows(1, postCount: 1));
      await tester.pump();
      requests[1].complete(_rows(4, postCount: 11));
      await tester.pump();
      final activity = container
          .read(venueStoryActivityProvider)
          .valueOrNull!['osm:node:123']!;
      expect(activity.count, 2);
      expect(activity.storyCount, 1);
      expect(activity.postCount, 1);
    } finally {
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
