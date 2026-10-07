import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/events/providers/event_provider.dart';
import 'package:night_owl_ub/features/events/providers/featured_events_provider.dart';
import 'package:night_owl_ub/features/events/widgets/featured_events_section.dart';
import 'package:night_owl_ub/features/feed/providers/reels_provider.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/map/screens/explore_screen.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_view.dart';
import 'package:night_owl_ub/models/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [true, false]) {
    testWidgets(
        'Explore scroll reaches events and videos and preserves map in ${dark ? 'night' : 'day'}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppColors.isDarkMode = dark;
      addTearDown(() => AppColors.isDarkMode = true);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            sessionUserIdProvider.overrideWithValue(null),
            currentProfileProvider.overrideWith((_) async => null),
            venuesProvider.overrideWith((_) async => []),
            featuredEventsProvider.overrideWith((_) async => []),
            reelsProvider.overrideWith((_) async => []),
          ],
          child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      disableAnimations: !dark,
                      textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              home: const ExploreScreen())));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(GoogleMapView));
      final controller =
          tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
      controller.move(const LatLng(47.923, 106.928), 18);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Эвент, богино видео үзэх'));
      await tester.tap(find.text('Эвент, богино видео үзэх'));
      await tester.pumpAndSettle();
      expect(find.text('Онцгой эвентүүд').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Богино бичлэгүүд'));
      expect(find.text('Богино бичлэгүүд').hitTestable(), findsOneWidget);
      expect(find.text('Шинэ бичлэгүүд удахгүй'), findsOneWidget);
      expect(find.byTooltip('Онцгой эвентүүд удирдах'), findsNothing);
      await tester.ensureVisible(find.text('Газрын зураг руу буцах'));
      await tester.tap(find.text('Газрын зураг руу буцах'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(GoogleMapView)), same(state));
      expect(controller.camera.zoom, 18);
      expect(controller.camera.center, const LatLng(47.923, 106.928));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'featured rail only renders curated events and admin control follows role',
      (tester) async {
    final role = StateProvider<bool>((_) => false);
    final container = ProviderContainer(overrides: [
      currentProfileProvider.overrideWith(
          (ref) async => UserProfile(id: 'fixture', isAdmin: ref.watch(role))),
      featuredEventsProvider.overrideWith((_) async => [
            EventItem(
                id: 'selected',
                title: 'Curated fixture night',
                startsAt: DateTime(2026, 12, 1))
          ]),
      upcomingEventsProvider.overrideWith((_) async => throw StateError(
          'Regular events must never become featured automatically')),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: FeaturedEventsSection()))));
    await tester.pumpAndSettle();
    expect(find.text('Curated fixture night'), findsOneWidget);
    expect(find.byTooltip('Онцгой эвентүүд удирдах'), findsNothing);
    container.read(role.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Онцгой эвентүүд удирдах'), findsOneWidget);
    container.read(role.notifier).state = false;
    await tester.pumpAndSettle();
    expect(find.byTooltip('Онцгой эвентүүд удирдах'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'featured loading ends with an honest retry and can recover empty',
      (tester) async {
    var attempts = 0;
    final pending = Completer<List<EventItem>>();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((_) async => null),
          featuredEventsProvider.overrideWith((_) {
            attempts++;
            return attempts == 1 ? pending.future : Future.value([]);
          }),
        ],
        child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: FeaturedEventsSection()))));
    await tester.pump();
    expect(find.text('Онцгой эвентүүдийг хайж байна…'), findsOneWidget);
    pending.completeError(StateError('fixture offline'));
    await tester.pumpAndSettle();
    expect(find.text('Онцгой эвентүүдийг ачаалж чадсангүй.'), findsOneWidget);
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
        find.text(
            'Шинэ сонголтууд удахгүй. Энд манай багийн онцолсон эвентүүд гарна.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
