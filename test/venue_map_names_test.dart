import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_view.dart';

void main() {
  const center = LatLng(47.9188126, 106.9168967);
  final rows = [
    {'id': 'a', 'name': 'Velora Lounge', 'type': 'lounge'},
    {
      'id': 'b',
      'name': 'Улаанбаатарын урт нэртэй хөгжмийн газар',
      'type': 'bar'
    },
    {'id': 'c', 'name': 'Moon', 'type': 'pub'},
  ];

  Future<MapController> show(WidgetTester tester,
      {bool dark = true,
      bool activity = true,
      bool neighbors = false,
      bool reducedMotion = true,
      double textScale = 1,
      String? selected,
      void Function(String)? onTap}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
            data: MediaQueryData(
                size: const Size(390, 844),
                disableAnimations: reducedMotion,
                textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
                body: GoogleMapView(
                    lat: center.latitude,
                    lng: center.longitude,
                    markersJson: jsonEncode([
                      for (var i = 0; i < rows.length; i++)
                        {
                          ...rows[i],
                          'lat': center.latitude,
                          'lng': center.longitude +
                              (neighbors ? i * 80 / (256 * 16384) * 360 : 0),
                        }
                    ]),
                    selectedId: selected,
                    activityCounts: activity ? {'a': 0, 'b': 8, 'c': 16} : null,
                    onVenueTap: onTap)))));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    controller.move(center, 18);
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('close zoom names are visible and tappable without opening a pin',
      (tester) async {
    final taps = <String>[];
    final controller = await show(tester, onTap: taps.add);
    final before = controller.camera.center;
    for (final row in rows) {
      final label = find.byKey(ValueKey('venue-name-${row['id']}'));
      expect(label, findsOneWidget);
      expect(find.descendant(of: label, matching: find.text(row['name']!)),
          findsOneWidget);
      await tester.tap(label);
      await tester.pumpAndSettle();
    }
    expect(taps, ['a', 'b', 'c']);
    expect(controller.camera.center, before);
    expect(controller.camera.zoom, 18);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('wide name does not steal taps beside a neighboring pin',
      (tester) async {
    final taps = <String>[];
    final controller = await show(tester,
        activity: false, neighbors: true, selected: 'b', onTap: taps.add);
    controller.move(center, 14);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byType(FlutterMap));
    final leftPin = origin + controller.camera.latLngToScreenOffset(center);
    await tester.tapAt(leftPin + const Offset(20, -35));
    expect(taps, ['a'],
        reason: 'Only the visible pin/caption should own pointer hits.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing text size with motion enabled never overflows a marker',
      (tester) async {
    await show(tester, activity: false, textScale: 2, reducedMotion: false);
    await show(tester, activity: false, textScale: 1, reducedMotion: false);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('venue-name-b')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final activity in [false, true]) {
    testWidgets(
        'name footer keeps the geographic pin tip with activity=$activity',
        (tester) async {
      final controller = await show(tester, activity: activity);
      final markers =
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
      final origin = tester.getTopLeft(find.byType(FlutterMap));
      for (final pin in markers) {
        final id = (pin.key! as ValueKey<String>).value;
        final label = tester.getRect(find.byKey(ValueKey('venue-name-$id')));
        final point =
            origin + controller.camera.latLngToScreenOffset(pin.point);
        expect(label.top - point.dy, closeTo(4, .01),
            reason: 'Caption sits below the actual pin tip, not in its place.');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final dark in [true, false]) {
    testWidgets(
        'large names remain separate, readable and accessible in ${dark ? 'night' : 'day'} mode',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final taps = <String>[];
      await show(tester,
          dark: dark, textScale: 2, selected: 'b', onTap: taps.add);
      final rects = [
        for (final row in rows)
          tester.getRect(find.byKey(ValueKey('venue-name-${row['id']}')))
      ];
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].height, greaterThanOrEqualTo(42));
        for (var j = 0; j < i; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
      expect(
          find.bySemanticsLabel(
              RegExp('Улаанбаатарын урт нэртэй хөгжмийн газар')),
          findsOneWidget,
          reason: 'Truncation must retain one complete spoken venue name.');
      await tester.tap(find.byKey(const ValueKey('venue-name-b')));
      expect(taps, ['b']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }
}
