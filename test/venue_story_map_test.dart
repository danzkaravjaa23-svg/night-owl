import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/map/providers/venue_story_activity_resolver.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_view.dart';
import 'package:night_owl_ub/features/map/widgets/venue_story_badge.dart';
import 'package:night_owl_ub/models/venue.dart';
import 'package:night_owl_ub/models/venue_story_activity.dart';

void main() {
  test('merged catalog aliases retain and sum story references exactly once',
      () {
    Venue venue(String id,
            {bool community = true, List<String> aliases = const []}) =>
        Venue(
            id: id,
            name: 'Same branch',
            type: 'pub',
            lat: 47.918,
            lng: 106.918,
            communityEnabled: community,
            catalogAliases: aliases,
            createdAt: DateTime(2026));
    final merged = mergeVenueCatalog([
      venue('uuid')
    ], [
      venue('osm:node:1', community: false),
      venue('osm:way:2', community: false)
    ]);
    expect(merged, hasLength(1));
    expect(merged.single.catalogAliases, ['osm:node:1', 'osm:way:2']);
    final activity = resolveVenueStoryActivity(merged.single, {
      'uuid': const VenueStoryActivity(count: 3),
      'osm:node:1': const VenueStoryActivity(count: 4),
      'osm:way:2': const VenueStoryActivity(count: 8),
      'elsewhere': const VenueStoryActivity(count: 99),
    });
    expect(activity.count, 15);
    expect(activity.level, VenueStoryLevel.onFire);
    expect(
        resolveVenueStoryActivity(venue('uuid', aliases: ['uuid', 'uuid']),
            {'uuid': const VenueStoryActivity(count: 3)}).count,
        3);
  });

  const rows = [
    {'id': 'a', 'name': 'Moon', 'type': 'pub', 'lat': 47.918, 'lng': 106.918},
    {'id': 'b', 'name': 'Ember', 'type': 'bar', 'lat': 47.919, 'lng': 106.92},
  ];

  Widget map(Map<String, int>? counts,
          {bool reduced = true,
          bool accessible = false,
          bool tickers = true,
          bool offstage = false}) =>
      MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(
                      disableAnimations: reduced,
                      accessibleNavigation: accessible),
                  child: TickerMode(
                      enabled: tickers,
                      child: Offstage(
                          offstage: offstage,
                          child: GoogleMapView(
                              lat: 47.918,
                              lng: 106.918,
                              zoom: 18,
                              markersJson: jsonEncode(rows),
                              activityCounts: counts))))));

  testWidgets(
      'unknown activity has no sleeping badges; success zero is sleeping',
      (tester) async {
    await tester.pumpWidget(map(null));
    await tester.pumpAndSettle();
    expect(find.byType(VenueStoryBadge), findsNothing);
    final tiles = tester.state(find.byType(TileLayer));
    await tester.pumpWidget(map({'a': 0, 'b': 15}));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TileLayer)), same(tiles));
    expect(
        tester
            .widgetList<VenueStoryBadge>(find.byType(VenueStoryBadge))
            .map((v) => v.level),
        containsAll([VenueStoryLevel.sleeping, VenueStoryLevel.onFire]));
    expect(
        find.byTooltip('Ember · 15 story · 0 post · Галтай'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all pins share continuous paint-only motion beyond one cycle',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(map({'a': 0, 'b': 15}, reduced: false));
    await tester.pump();
    final phases = tester
        .widgetList<VenueStoryBadge>(find.byType(VenueStoryBadge))
        .map((badge) => badge.phase)
        .toList();
    expect(phases, hasLength(2));
    expect(phases[1], same(phases[0]),
        reason: 'Visible pins share one controller, including sleeping pins.');
    final phase = phases.first as AnimationController;
    expect(phase.duration, const Duration(seconds: 6));
    final mapState = tester.state(find.byType(GoogleMapView));
    final tiles = tester.state(find.byType(TileLayer));
    final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
    await tester.pump(const Duration(milliseconds: 700));
    final first = phase.value;
    expect(first, greaterThan(0));
    await tester.pump(const Duration(seconds: 6));
    expect(phase.value, closeTo(first, .001));
    expect(phase.isAnimating, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(phase.value, greaterThan(first));
    expect(tester.state(find.byType(GoogleMapView)), same(mapState));
    expect(tester.state(find.byType(TileLayer)), same(tiles));
    expect(tester.widget<TileLayer>(find.byType(TileLayer)), same(tileLayer));
    expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)), same(markerLayer),
        reason: 'Paint-only frames do not rebuild markers or camera.');
    expect(
        MapCamera.of(tester.element(find.byType(MarkerLayer))), same(camera));
    await tester.pumpWidget(const SizedBox());
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready activity refreshes preserve the shared motion phase',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(map({'a': 2, 'b': 7}, reduced: false));
    await tester.pump();
    final phase = tester
        .widget<VenueStoryBadge>(find.byType(VenueStoryBadge).first)
        .phase as AnimationController;
    await tester.pump(const Duration(milliseconds: 1200));
    final beforeRefresh = phase.value;
    await tester.pumpWidget(map({'a': 2, 'b': 7}, reduced: false));
    expect(
        tester
            .widget<VenueStoryBadge>(find.byType(VenueStoryBadge).first)
            .phase,
        same(phase));
    expect(phase.value, closeTo(beforeRefresh, .001));
    await tester.pump(const Duration(milliseconds: 600));
    final beforeNewCounts = phase.value;
    await tester.pumpWidget(map({'a': 0, 'b': 15}, reduced: false));
    expect(phase.value, closeTo(beforeNewCounts, .001),
        reason: 'Polling/count changes must not restart every marker.');
    expect(
        tester
            .widgetList<VenueStoryBadge>(find.byType(VenueStoryBadge))
            .map((badge) => badge.level),
        containsAll([VenueStoryLevel.sleeping, VenueStoryLevel.onFire]));
    await tester.pump(const Duration(milliseconds: 600));
    expect(phase.value, greaterThan(beforeNewCounts));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion preferences and hidden TickerMode stop and resume motion',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    const counts = {'a': 0, 'b': 15};
    await tester.pumpWidget(map(counts, reduced: false));
    await tester.pump();
    final phase = tester
        .widget<VenueStoryBadge>(find.byType(VenueStoryBadge).first)
        .phase as AnimationController;
    for (final stopped in [
      map(counts),
      map(counts, reduced: false, accessible: true),
      map(counts, reduced: false, tickers: false),
      // Flutter Offstage retains the map cache; its TickerMode is disabled
      // by the app while the list view covers the map.
      map(counts, reduced: false, tickers: false, offstage: true),
    ]) {
      await tester.pump(const Duration(milliseconds: 500));
      expect(phase.value, greaterThan(0));
      await tester.pumpWidget(stopped);
      expect(phase.value, 0);
      expect(phase.isAnimating, isFalse);
      await tester.pump(const Duration(seconds: 8));
      expect(phase.value, 0);
      expect(phase.isAnimating, isFalse,
          reason: 'The badge clock stays stopped independently of tile fades.');
      await tester.pumpWidget(map(counts, reduced: false));
      await tester.pump();
      expect(phase.isAnimating, isTrue);
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(phase.value, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background, unavailable activity and disposal leave no ticker',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(map({'a': 0, 'b': 15}, reduced: false));
    await tester.pump();
    final phase = tester
        .widget<VenueStoryBadge>(find.byType(VenueStoryBadge).first)
        .phase as AnimationController;
    await tester.pump(const Duration(milliseconds: 600));
    expect(phase.value, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(phase.value, 0);
    expect(phase.isAnimating, isFalse);
    await tester.pump(const Duration(seconds: 8));
    expect(phase.value, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(phase.value, greaterThan(0));
    await tester.pumpWidget(map(null, reduced: false));
    expect(find.byType(VenueStoryBadge), findsNothing);
    expect(phase.value, 0);
    expect(phase.isAnimating, isFalse);
    await tester.pump(const Duration(seconds: 8));
    expect(phase.value, 0);
    expect(phase.isAnimating, isFalse);
    await tester.pumpWidget(map({'a': 0, 'b': 15}, reduced: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(phase.value, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map created inactive waits for foreground before ticking',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(map({'a': 0, 'b': 15}, reduced: false));
    await tester.pump();
    final phase = tester
        .widget<VenueStoryBadge>(find.byType(VenueStoryBadge).first)
        .phase as AnimationController;
    await tester.pump(const Duration(seconds: 8));
    expect(phase.value, 0);
    expect(phase.isAnimating, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(phase.value, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('legend fits 320px with large text in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(1.5)),
                  child: VenueStoryLegend()))));
      await tester.pumpAndSettle();
      expect(find.byType(VenueStoryBadge), findsNWidgets(4));
      expect(find.text('15+ идэвх'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('weekly posts contribute to pin level with separate counts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: GoogleMapView(
                    lat: 47.918,
                    lng: 106.918,
                    zoom: 18,
                    markersJson: jsonEncode(rows),
                    activityCounts: const {'a': 5, 'b': 15},
                    activityPostCounts: const {'a': 4, 'b': 15})))));
    await tester.pumpAndSettle();
    expect(
        find.byTooltip('Moon · 1 story · 4 post · Идэвхтэй'), findsOneWidget);
    expect(
        find.byTooltip('Ember · 0 story · 15 post · Галтай'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'same total with changed private post breakdown closes group sheet',
      (tester) async {
    Widget scene(Map<String, int> posts) => MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: GoogleMapView(
                    lat: 47.918,
                    lng: 106.918,
                    zoom: 14,
                    markersJson: jsonEncode([
                      for (final id in ['a', 'b'])
                        {
                          'id': id,
                          'name': 'Venue $id',
                          'lat': 47.918,
                          'lng': 106.918
                        }
                    ]),
                    activityCounts: const {'a': 3, 'b': 2},
                    activityPostCounts: posts))));
    await tester.pumpWidget(scene({'a': 2, 'b': 2}));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byTooltip('2 газар · 1 story · 4 post · Газруудыг харах'));
    await tester.pumpAndSettle();
    expect(find.text('1 story · 4 post'), findsOneWidget);
    await tester.pumpWidget(scene({'a': 1, 'b': 1}));
    await tester.pumpAndSettle();
    expect(find.text('1 story · 4 post'), findsNothing);
    expect(find.byKey(const ValueKey('venue-group-member-a')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('open group sheet clears private counts on activity invalidation',
      (tester) async {
    Widget scene(Map<String, int>? counts) => MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: GoogleMapView(
                    lat: 47.918,
                    lng: 106.918,
                    zoom: 14,
                    markersJson: jsonEncode([
                      for (final id in ['a', 'b'])
                        {
                          'id': id,
                          'name': 'Venue $id',
                          'lat': 47.918,
                          'lng': 106.918
                        },
                    ]),
                    activityCounts: counts))));
    await tester.pumpWidget(scene({'a': 1, 'b': 2}));
    await tester.pumpAndSettle();
    final tiles = tester.state(find.byType(TileLayer));
    await tester
        .tap(find.byTooltip('2 газар · 3 story · 0 post · Газруудыг харах'));
    await tester.pumpAndSettle();
    expect(find.text('3 story · 0 post'), findsOneWidget);
    expect(find.byKey(const ValueKey('venue-group-member-a')), findsOneWidget);
    await tester.pumpWidget(scene(null));
    await tester.pumpAndSettle();
    expect(find.text('3 story · 0 post'), findsNothing);
    expect(find.byKey(const ValueKey('venue-group-member-a')), findsNothing);
    expect(tester.state(find.byType(TileLayer)), same(tiles));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
