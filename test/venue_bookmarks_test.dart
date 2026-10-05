import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  Future<void> pumpExplore(WidgetTester tester, List<Venue> venues) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('test-account'),
          venuesProvider.overrideWith((ref) async => venues),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const ExploreScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Explore opens the map but its list keeps unlocated venues discoverable at 320px',
      (tester) async {
    final venue = Venue(
        id: 'unlocated',
        name: 'Unlocated test venue',
        type: 'pub',
        createdAt: DateTime(2026));
    await pumpExplore(tester, [venue]);
    expect(find.byType(GoogleMapView), findsOneWidget);
    expect(find.text('Эдгээр газрын байршил хараахан бүртгэгдээгүй.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Бүх газрыг жагсаалтаар харах'));
    await tester.pumpAndSettle();
    expect(find.text('Unlocated test venue'), findsOneWidget);
    expect(find.text('Байршил нэмэгдээгүй'), findsOneWidget);
    await tester.tap(find.byTooltip('Газар хадгалах'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('venue_bookmarks.test-account'), ['unlocated']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a selected venue card scrolls, saves and closes without invented ratings at 320px',
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
    await pumpExplore(tester, [venue]);
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
