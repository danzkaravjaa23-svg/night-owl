import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/map/screens/explore_screen.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_view.dart';
import 'package:night_owl_ub/models/venue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selecting an individual map pin keeps close zoom and placement',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final venues = [
      for (final id in ['a', 'b', 'c'])
        Venue(
            id: id,
            name: 'Test venue $id',
            type: 'pub',
            lat: 47.923,
            lng: 106.928,
            createdAt: DateTime(2026)),
    ];
    await tester.pumpWidget(ProviderScope(overrides: [
      sessionUserIdProvider.overrideWithValue(null),
      venuesProvider.overrideWith((_) async => venues),
    ], child: MaterialApp(theme: AppTheme.dark, home: const ExploreScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Сонголт хаах'));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    controller.move(const LatLng(47.923, 106.928), 18.5);
    await tester.pumpAndSettle();
    final positions = {
      for (final marker
          in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers)
        marker.key: marker.point
    };
    await tester.tap(find.byTooltip('Test venue b'));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, 18.5);
    expect(controller.camera.center, const LatLng(47.923, 106.928));
    expect(tester.widget<GoogleMapView>(find.byType(GoogleMapView)).selectedId,
        'b');
    final markers =
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(markers.last.key, const ValueKey('b'));
    expect({for (final marker in markers) marker.key: marker.point}, positions);
    expect(find.byTooltip('Сонголт хаах'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('map/list switching keeps tiles mounted and camera position',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(overrides: [
      sessionUserIdProvider.overrideWithValue(null),
      venuesProvider.overrideWith((_) async => <Venue>[]),
    ], child: MaterialApp(theme: AppTheme.dark, home: const ExploreScreen())));
    await tester.pumpAndSettle();
    final renderer = tester.state(find.byType(GoogleMapView));
    final tiles = tester.state(find.byType(TileLayer));
    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    controller.move(const LatLng(47.923, 106.928), 15);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Бүх газрыг жагсаалтаар харах'));
    await tester.pumpAndSettle();
    expect(renderer.mounted, isTrue,
        reason: 'List view must not destroy the tile cache and map camera.');
    expect(tiles.mounted, isTrue);
    expect(find.byType(GoogleMapView), findsNothing);

    await tester.tap(find.byTooltip('Газрын зураг харах'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(GoogleMapView)), same(renderer));
    expect(tester.state(find.byType(TileLayer)), same(tiles));
    expect(controller.camera.center, const LatLng(47.923, 106.928));
    expect(controller.camera.zoom, 15);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
