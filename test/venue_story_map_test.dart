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

  Widget map(Map<String, int>? counts, {bool reduced = true}) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
          body: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: GoogleMapView(
                  lat: 47.918,
                  lng: 106.918,
                  zoom: 18,
                  markersJson: jsonEncode(rows),
                  activityCounts: counts))));

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
    expect(find.byTooltip('Ember · Өнөөдөр 15 story · Галтай'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('badge motion settles and does not recreate map tiles',
      (tester) async {
    await tester.pumpWidget(map({'a': 2, 'b': 7}, reduced: false));
    await tester.pump();
    final tiles = tester.state(find.byType(TileLayer));
    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.state(find.byType(TileLayer)), same(tiles));
    expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)), same(markerLayer),
        reason: 'Paint-only frames do not rebuild markers or camera.');
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox());
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
      expect(find.text('15+ story'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
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
        .tap(find.byTooltip('2 газар · Өнөөдөр 3 story · Газруудыг харах'));
    await tester.pumpAndSettle();
    expect(find.text('Өнөөдөр 3 story'), findsOneWidget);
    expect(find.byKey(const ValueKey('venue-group-member-a')), findsOneWidget);
    await tester.pumpWidget(scene(null));
    await tester.pumpAndSettle();
    expect(find.text('Өнөөдөр 3 story'), findsNothing);
    expect(find.byKey(const ValueKey('venue-group-member-a')), findsNothing);
    expect(tester.state(find.byType(TileLayer)), same(tiles));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
