import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_view.dart';

VenueMapMarker marker(String id, double pixels) => VenueMapMarker(
    id,
    'Газар $id',
    'pub',
    LatLng(47.9188126, 106.9168967 + pixels / (256 * math.pow(2, 14)) * 360));

List<List<String>> membership(List<VenueMarkerGroup> groups) => [
      for (final group in groups) group.members.map((v) => v.id).toList(),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final line = [marker('a', 0), marker('b', 60), marker('c', 120)];

  test(
      'grouping is stable, bounded and preserves every member without chaining',
      () {
    final groups = VenueMarkerGrouping.group(line, zoom: 14);
    expect(membership(groups), [
      ['a', 'b'],
      ['c']
    ]);
    expect(
        membership(VenueMarkerGrouping.group(line.reversed.toList(), zoom: 14)),
        membership(groups),
        reason: 'Backend row order cannot move anchors or change counts.');
    expect(groups.first.point, line.first.point);
    expect(groups.first.isCoincident, isFalse);
    expect(() => groups.first.members.clear(), throwsUnsupportedError);
  });

  test(
      'closer zoom separates neighbors and selected members stay visible and last',
      () {
    expect(membership(VenueMarkerGrouping.group(line, zoom: 19)), [
      ['a'],
      ['b'],
      ['c']
    ]);
    final selected = VenueMarkerGrouping.group(line, zoom: 14, selectedId: 'b');
    expect(membership(selected), [
      ['a'],
      ['c'],
      ['b']
    ]);
    expect(selected.last.isCluster, isFalse);
    expect(selected.expand((g) => g.members).map((v) => v.id).toSet(),
        {'a', 'b', 'c'});
    expect(VenueMarkerGrouping.zoomBucket(14.49), 14);
    expect(VenueMarkerGrouping.zoomBucket(14.5), 14.5);
  });

  test('coincident venues stay reachable in one group even at maximum zoom',
      () {
    final same = [
      for (var i = 0; i < 30; i++)
        marker('id-${i.toString().padLeft(2, '0')}', 0)
    ];
    final groups = VenueMarkerGrouping.group(same, zoom: 19);
    expect(groups, hasLength(1));
    expect(groups.single.isCoincident, isTrue);
    expect(groups.single.members, hasLength(30));
  });

  test('real catalog overview groups density without hiding any of270 venues',
      () async {
    final catalog = jsonDecode(await rootBundle
        .loadString('assets/data/ulaanbaatar_osm_venues.json')) as Map;
    final rows = (catalog['venues'] as List).cast<Map>();
    final markers = [
      for (final row in rows)
        VenueMapMarker(
            row['id'] as String,
            row['name'] as String,
            row['venue_type'] as String,
            LatLng(
                (row['lat'] as num).toDouble(), (row['lng'] as num).toDouble()))
    ];
    final groups = VenueMarkerGrouping.group(markers, zoom: 14);
    expect(markers, hasLength(270));
    expect(groups.length, lessThan(35));
    final ids = groups.expand((g) => g.members).map((v) => v.id).toList();
    expect(ids, hasLength(markers.length));
    expect(ids.toSet(), markers.map((v) => v.id).toSet());
    expect(ids.toSet().length, ids.length,
        reason: 'No duplicate or lost member.');
  });

  Future<MapController> render(WidgetTester tester, List<VenueMapMarker> venues,
      {String? selected,
      bool reduced = false,
      bool accessible = false,
      double textScale = 1,
      double inset = 0,
      void Function(String)? onTap}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final encoded = jsonEncode([
      for (final venue in venues)
        {
          'id': venue.id,
          'name': venue.name,
          'type': venue.type,
          'lat': venue.point.latitude,
          'lng': venue.point.longitude,
        }
    ]);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: reduced,
          accessibleNavigation: accessible,
          textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
          body: GoogleMapView(
              lat: 47.9188126,
              lng: 106.9168967,
              markersJson: encoded,
              selectedId: selected,
              bottomInset: inset,
              onVenueTap: onTap)),
    )));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    controller.move(const LatLng(47.9188126, 106.9168967), 14);
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
      'group tap fits members, panning and zooming preserve map and tile state',
      (tester) async {
    final controller = await render(
        tester, [marker('a', 0), marker('b', 30), marker('c', 140)]);
    final mapState = tester.state(find.byType(GoogleMapView));
    final tileState = tester.state(find.byType(TileLayer));
    final initialKeys = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers
        .map((m) => m.key)
        .toList();
    controller.move(const LatLng(47.919, 106.917), 14.2);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers
            .map((m) => m.key),
        initialKeys);
    await tester.tap(find.byTooltip('2 газар · Газруудыг харах'));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, greaterThan(14.2));
    expect(
        controller.camera.visibleBounds.contains(marker('a', 0).point), isTrue);
    expect(controller.camera.visibleBounds.contains(marker('b', 30).point),
        isTrue);
    expect(tester.state(find.byType(GoogleMapView)), same(mapState));
    expect(tester.state(find.byType(TileLayer)), same(tileState));
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'selected group member has its own venue action above the count bubble',
      (tester) async {
    final taps = <String>[];
    await render(tester, [marker('a', 0), marker('b', 10), marker('c', 20)],
        selected: 'b', onTap: taps.add);
    final markers =
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(markers, hasLength(2));
    expect(markers.last.key, const ValueKey('b'));
    await tester.tap(find.byTooltip('Газар b'));
    await tester.pumpAndSettle();
    expect(taps, ['b']);
    expect(find.byTooltip('2 газар · Газруудыг харах'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final accessible in [false, true]) {
    testWidgets(
        'coincident chooser reaches last member with large text and reduced ${accessible ? 'navigation' : 'motion'}',
        (tester) async {
      final same = [
        for (var i = 0; i < 30; i++)
          marker('id-${i.toString().padLeft(2, '0')}', 0)
      ];
      final taps = <String>[];
      await render(tester, same,
          reduced: !accessible,
          accessible: accessible,
          textScale: 1.5,
          onTap: taps.add);
      await tester.tap(find.byTooltip('30 газар · Газруудыг харах'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<BottomSheet>(find.byType(BottomSheet))
              .animationController!
              .duration,
          Duration.zero);
      final last = find.byKey(const ValueKey('venue-group-member-id-29'));
      await tester.scrollUntilVisible(last, 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(taps, ['id-29']);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'nearby distinct venues at maximum zoom open chooser without a no-op fit',
      (tester) async {
    final taps = <String>[];
    final controller = await render(tester, [marker('a', 0), marker('b', .4)],
        onTap: taps.add);
    controller.move(const LatLng(47.9188126, 106.9168967), 19);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('2 газар · Газруудыг харах'));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, 19);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('venue-group-member-b')));
    await tester.pumpAndSettle();
    expect(taps, ['b']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
