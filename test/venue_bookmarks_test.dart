import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/widgets/sculpted_icon.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/map/screens/explore_screen.dart';
import 'package:night_owl_ub/features/map/screens/map_screen.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_view.dart';
import 'package:night_owl_ub/models/venue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved venues persist and restore for the same account', () async {
    final first = VenueBookmarksNotifier('one');
    await first.ready;
    await first.toggle('venue-b');
    await first.toggle('venue-a');
    expect(first.state.valueOrNull, {'venue-a', 'venue-b'});
    first.dispose();
    final restored = VenueBookmarksNotifier('one');
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.valueOrNull, {'venue-a', 'venue-b'});
    await restored.toggle('venue-a');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(restored.storageKey), ['venue-b']);
  });

  test(
      'changing accounts or using a guest never shows another account bookmarks',
      () async {
    SharedPreferences.setMockInitialValues({
      'venue_bookmarks.one': ['private-place']
    });
    final one = VenueBookmarksNotifier('one');
    final two = VenueBookmarksNotifier('two');
    final guest = VenueBookmarksNotifier(null);
    addTearDown(() {
      one.dispose();
      two.dispose();
      guest.dispose();
    });
    await Future.wait([one.ready, two.ready, guest.ready]);
    expect(one.state.valueOrNull, {'private-place'});
    expect(two.state.valueOrNull, isEmpty);
    expect(guest.state.valueOrNull, isEmpty);
    await two.toggle('another-place');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(one.storageKey), ['private-place']);
    expect(prefs.getStringList(two.storageKey), ['another-place']);
  });

  test('rapid concurrent saves cannot silently undo a bookmark', () async {
    final bookmarks = VenueBookmarksNotifier('one');
    addTearDown(bookmarks.dispose);
    await bookmarks.ready;
    final pending = bookmarks.toggle('venue');
    await expectLater(bookmarks.toggle('venue'), throwsStateError);
    await pending;
    expect(bookmarks.state.valueOrNull, {'venue'});
  });

  test('a late load or save is safe after bookmarks are disposed', () async {
    final bookmarks = VenueBookmarksNotifier('one');
    bookmarks.dispose();
    await bookmarks.ready;
    await bookmarks.toggle('late-venue');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('venue_bookmarks.one'), isFalse);
  });

  test('unreadable stored bookmarks are not replaced by an empty save',
      () async {
    SharedPreferences.setMockInitialValues(
        {'venue_bookmarks.one': 'damaged-storage'});
    final bookmarks = VenueBookmarksNotifier('one');
    addTearDown(bookmarks.dispose);
    await bookmarks.ready;
    expect(bookmarks.state.hasError, isTrue);
    await expectLater(bookmarks.toggle('new-place'), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(bookmarks.storageKey), 'damaged-storage');
  });

  Future<void> pumpExplore(WidgetTester tester, List<Venue> venues,
      {bool dark = true}) async {
    AppColors.isDarkMode = dark;
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AppColors.isDarkMode = true;
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('test-account'),
          venuesProvider.overrideWith((ref) async => venues),
        ],
        child: MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const ExploreScreen())));
    await tester.pumpAndSettle();
  }

  for (final dark in [true, false]) {
    testWidgets(
        'Explore map/list stay readable and functional at 320px in ${dark ? 'night' : 'day'} mode',
        (tester) async {
      final venue = Venue(
          id: 'unlocated',
          name: 'Unlocated test venue',
          type: 'pub',
          createdAt: DateTime(2026));
      await pumpExplore(tester, [venue], dark: dark);
      expect(find.byType(GoogleMapView), findsOneWidget);
      expect(
          tester
              .widget<Scaffold>(find
                  .descendant(
                      of: find.byType(MapScreen),
                      matching: find.byType(Scaffold))
                  .first)
              .backgroundColor,
          dark ? AppColors.bgBaseDark : AppColors.bgBaseLight);
      expect(tester.widget<Text>(find.text('Explore')).style?.color,
          dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);
      final filter = tester
          .widget<ColorFiltered>(find
              .descendant(
                  of: find.byType(GoogleMapView),
                  matching: find.byType(ColorFiltered))
              .first)
          .colorFilter;
      const natural = ColorFilter.mode(Colors.transparent, BlendMode.dst);
      expect(filter, dark ? isNot(equals(natural)) : equals(natural));
      expect(find.byType(SculptedIcon), findsWidgets);
      expect(find.text('Эдгээр газрын байршил хараахан бүртгэгдээгүй.'),
          findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.text('Эдгээр газрын байршил хараахан бүртгэгдээгүй.'))
              .style
              ?.color,
          dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);
      await tester.tap(find.byTooltip('Бүх газрыг жагсаалтаар харах'));
      await tester.pumpAndSettle();
      expect(find.text('Unlocated test venue'), findsOneWidget);
      expect(find.text('Байршил нэмэгдээгүй'), findsOneWidget);
      await tester.tap(find.byTooltip('Газар хадгалах'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getStringList('venue_bookmarks.test-account'), ['unlocated']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'selected venue card scrolls, saves and closes at 320px in ${dark ? 'night' : 'day'} mode',
        (tester) async {
      await Supabase.initialize(
          url: 'https://example.test',
          anonKey: 'test-only-anon-key',
          debug: false,
          httpClient: MockClient((request) async => http.Response(
              '{"description":"An actual test description loaded from the fixture."}',
              200,
              headers: {'content-type': 'application/json'},
              request: request)),
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false,
              detectSessionInUri: false,
              localStorage: EmptyLocalStorage()));
      addTearDown(() async => Supabase.instance.dispose());
      final venue = Venue(
          id: 'located',
          name: 'Long test venue name',
          type: 'pub',
          lat: 47.9152,
          lng: 106.9174,
          address: 'Test address',
          createdAt: DateTime(2026));
      await pumpExplore(tester, [venue], dark: dark);
      expect(find.text('Үнэлгээ хараахан алга'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      await tester.ensureVisible(find.byTooltip('Газар хадгалах'));
      await tester.tap(find.byTooltip('Газар хадгалах'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('venue_bookmarks.test-account'), ['located']);
      await tester.ensureVisible(find.byTooltip('Сонголт хаах'));
      await tester.tap(find.byTooltip('Сонголт хаах'));
      await tester.pumpAndSettle();
      expect(find.text('Чиглэл авах'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'switching theme preserves the interactive map camera and changes tile styling',
      (tester) async {
    final mode = ValueNotifier(true);
    addTearDown(() {
      mode.dispose();
      AppColors.isDarkMode = true;
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('test-account'),
          venuesProvider.overrideWith((ref) async => <Venue>[]),
        ],
        child: ValueListenableBuilder<bool>(
            valueListenable: mode,
            builder: (_, dark, __) {
              AppColors.isDarkMode = dark;
              return MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  home: const ExploreScreen());
            })));
    await tester.pumpAndSettle();
    final renderer = tester.state(find.byType(GoogleMapView));
    final controller =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    controller.move(const LatLng(47.92, 106.92), 15);
    await tester.pumpAndSettle();
    mode.value = false;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(GoogleMapView)), same(renderer));
    expect(tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController,
        same(controller));
    expect(controller.camera.center, const LatLng(47.92, 106.92));
    expect(controller.camera.zoom, 15);
    expect(
        tester
            .widget<ColorFiltered>(find
                .descendant(
                    of: find.byType(GoogleMapView),
                    matching: find.byType(ColorFiltered))
                .first)
            .colorFilter,
        const ColorFilter.mode(Colors.transparent, BlendMode.dst));
    expect(tester.takeException(), isNull);
  });
}
