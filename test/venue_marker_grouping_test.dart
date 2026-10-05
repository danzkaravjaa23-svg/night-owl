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

  test('close zoom exposes every coincident venue as an individual pin', () {
    final same = [
      for (var i = 0; i < 30; i++)
        marker('id-${i.toString().padLeft(2, '0')}', 0)
    ];
    expect(VenueMarkerGrouping.group(same, zoom: 17.99), hasLength(1));
    for (final zoom in [18.0, 18.49, 18.5, 19.0]) {
      final groups = VenueMarkerGrouping.group(same, zoom: zoom);
      expect(groups, hasLength(30));
      expect(groups.every((group) => !group.isCluster), isTrue);
      expect(groups.map((group) => group.members.single.id),
          same.map((venue) => venue.id));
    }
  });

  test(
      'dense close pins have separate hit areas without changing true locations',
      () {
    final venues = [
      for (var i = 0; i < 30; i++)
        marker('id-${i.toString().padLeft(2, '0')}', i % 3 * .4)
    ];
    final original = {for (final venue in venues) venue.id: venue.point};
    for (final zoom in [18.0, 18.49, 18.5, 19.0]) {
      final positions = VenuePinLayout.positions(venues, zoom: zoom);
      expect(positions.keys.toSet(), original.keys.toSet());
      expect(positions,
          VenuePinLayout.positions(venues.reversed.toList(), zoom: zoom),
          reason: 'Backend ordering cannot reshuffle close venues.');
      final scale = 256 * math.pow(2, zoom);
      Offset project(LatLng point) {
        final sin = math.sin(point.latitude * math.pi / 180);
        return Offset((point.longitude + 180) / 360 * scale,
            (.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale);
      }

      final projected = positions.values.map(project).toList();
      for (var i = 0; i < projected.length; i++) {
        for (var j = 0; j < i; j++) {
          final delta = projected[i] - projected[j];
          expect(delta.dx.abs() >= 59.99 || delta.dy.abs() >= 75.99, isTrue,
              reason: 'The entire 52×64 touch rectangles must stay separate.');
        }
      }
      expect({for (final venue in venues) venue.id: venue.point}, original,
          reason: 'Directions and venue data must use the real coordinates.');
    }
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

  for (final zoom in [18.0, 19.0]) {
    testWidgets(
        'zoom $zoom permits direct taps on coincident and nearby pins and zoom out restores counts',
        (tester) async {
      final venues = [marker('a', 0), marker('b', 0), marker('c', .4)];
      final original = {for (final venue in venues) venue.id: venue.point};
      final taps = <String>[];
      final controller = await render(tester, venues, onTap: taps.add);
      final mapState = tester.state(find.byType(GoogleMapView));
      final tileState = tester.state(find.byType(TileLayer));
      controller.move(const LatLng(47.9188126, 106.9168967), zoom);
      await tester.pumpAndSettle();
      expect(find.byTooltip('3 газар · Газруудыг харах'), findsNothing);
      final rectangles = [
        for (final venue in venues) tester.getRect(find.byTooltip(venue.name))
      ];
      for (var i = 0; i < rectangles.length; i++) {
        for (var j = 0; j < i; j++) {
          expect(rectangles[i].overlaps(rectangles[j]), isFalse);
        }
      }
      for (final venue in venues) {
        await tester.tap(find.byTooltip(venue.name));
        await tester.pumpAndSettle();
      }
      expect(taps, ['a', 'b', 'c']);
      expect(controller.camera.zoom, zoom);
      expect(find.byType(BottomSheet), findsNothing);
      final markers =
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
      final displayPositions = {for (final pin in markers) pin.key: pin.point};
      final leaders = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(leaders.polylines, hasLength(2));
      for (final venue in venues.skip(1)) {
        expect(
            leaders.polylines.any((line) =>
                line.points.first == venue.point &&
                line.points.last == displayPositions[ValueKey(venue.id)]),
            isTrue,
            reason:
                'Offset pins remain visibly connected to their real place.');
      }
      expect({for (final venue in venues) venue.id: venue.point}, original);

      controller.move(const LatLng(47.9189, 106.9169), zoom);
      await tester.pumpAndSettle();
      expect({
        for (final pin
            in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers)
          pin.key: pin.point
      }, displayPositions, reason: 'Panning must not rearrange close pins.');
      controller.move(const LatLng(47.9188126, 106.9168967), 17.99);
      await tester.pumpAndSettle();
      expect(find.byTooltip('3 газар · Газруудыг харах'), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(tester.state(find.byType(GoogleMapView)), same(mapState));
      expect(tester.state(find.byType(TileLayer)), same(tileState));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'selecting a close pin only raises it without rearranging its peers',
      (tester) async {
    final venues = [marker('a', 0), marker('b', 0), marker('c', .4)];
    final controller = await render(tester, venues);
    controller.move(const LatLng(47.9188126, 106.9168967), 18);
    await tester.pumpAndSettle();
    Map<Key?, LatLng> positions() => {
          for (final pin
              in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers)
            pin.key: pin.point
        };
    final before = positions();
    final taps = <String>[];
    final updated = await render(tester, venues.reversed.toList(),
        selected: 'b', onTap: taps.add);
    updated.move(const LatLng(47.9188126, 106.9168967), 18);
    await tester.pumpAndSettle();
    expect(positions(), before);
    expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.last.key,
        const ValueKey('b'));
    await tester.tap(find.byTooltip('Газар b'));
    await tester.pumpAndSettle();
    expect(taps, ['b']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
