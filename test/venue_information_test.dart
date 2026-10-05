import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/map/screens/explore_screen.dart';
import 'package:night_owl_ub/features/map/widgets/venue_information_sheet.dart';
import 'package:night_owl_ub/models/venue.dart';

Venue catalogVenue(
        {String name = 'Бодит кафе',
        String? website = 'https://cafe.example.test/menu'}) =>
    Venue(
      id: 'osm:node:123',
      name: name,
      type: 'cafe',
      lat: 47.918,
      lng: 106.919,
      createdAt: DateTime.utc(2026, 10, 5),
      communityEnabled: false,
      address: 'Улаанбаатар, Энхтайваны өргөн чөлөө',
      phone: '+976 1234 5678',
      sourceLabel: 'OpenStreetMap',
      sourceUrl: 'https://www.openstreetmap.org/node/123',
      sourceRetrievedAt: DateTime.utc(2026, 10, 5),
      sourceOpeningHours: 'Mo-Su 09:00-23:00',
      websiteUrl: website,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('public Google Maps search uses place name/address, no user position',
      () {
    final url = venueGoogleMapsUrl(catalogVenue());
    expect(url.scheme, 'https');
    expect(url.host, 'www.google.com');
    expect(url.queryParameters['api'], '1');
    expect(url.queryParameters['query'], contains('Бодит кафе'));
    expect(url.queryParameters['query'], contains('Энхтайваны'));
    expect(url.queryParameters.containsKey('origin'), isFalse);
    expect(
        venueGoogleMapsUrl(catalogVenue(name: '🌃' * 1500)).toString().length,
        lessThan(2048));
  });

  test(
      'website/phone reject unsupported schemes, credentials and injected numbers',
      () {
    for (final value in [
      'javascript:alert(1)',
      'data:text/html,hello',
      'https://user:pass@example.test',
      'file:///tmp/test',
      ''
    ]) {
      expect(venueWebsiteUrl(value), isNull);
    }
    expect(venueWebsiteUrl('https://cafe.example.test/menu')!.host,
        'cafe.example.test');
    expect(venuePhoneUrl('+976 (1234) 5678; +976 8765 4321').toString(),
        'tel:+97612345678');
    for (final value in [
      '12',
      '+97612345?x=1',
      'javascript:12345',
      '1234567890123456'
    ]) {
      expect(venuePhoneUrl(value), isNull);
    }
  });

  testWidgets('owned schedule wins over older public source schedule',
      (tester) async {
    final venue = Venue(
      id: '00000000-0000-4000-8000-000000000001',
      name: 'Owned Pub',
      type: 'pub',
      createdAt: DateTime.utc(2026),
      openTime: '21:00',
      closeTime: '05:00',
      openingHours: const {'fri': '20:00-04:00', 'mon': '18:00-01:00'},
      sourceOpeningHours: 'Mo-Su 09:00-23:00',
      sourceLabel: 'OpenStreetMap',
    );
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: VenueInformationSheet(venue: venue))));
    await tester.pumpAndSettle();
    expect(find.text('Газрын бүртгэлийн цаг'), findsOneWidget);
    expect(
        find.text('Даваа: 18:00-01:00\nБаасан: 20:00-04:00'), findsOneWidget);
    expect(find.text('Mo-Su 09:00-23:00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'catalog sheet supports 320px large text and failed link retry in $brightness',
        (tester) async {
      final theme =
          brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <Uri>[];
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 720),
                textScaler: TextScaler.linear(1.4),
                disableAnimations: true),
            child: Scaffold(
                body: VenueInformationSheet(
                    venue: catalogVenue(),
                    openUri: (uri) async {
                      calls.add(uri);
                      return calls.length > 1;
                    })),
          )));
      await tester.pumpAndSettle();
      expect(find.text('Бодит кафе'), findsOneWidget);
      expect(find.text('Үнэлгээ хараахан алга'), findsNothing);
      await tester.ensureVisible(find.text('Google Maps-д харах'));
      await tester.tap(find.text('Google Maps-д харах'));
      await tester.pumpAndSettle();
      expect(calls.single, venueGoogleMapsUrl(catalogVenue()));
      expect(
          find.text('Холбоос нээгдсэнгүй. Дахин оролдоорой.'), findsOneWidget);
      await tester.tap(find.text('Google Maps-д харах'));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(find.text('Холбоос нээгдсэнгүй. Дахин оролдоорой.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        '320px large-text catalog opens public information without community queries in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // No Supabase singleton is initialized: any community query would fail.
      await tester.pumpWidget(ProviderScope(
          overrides: [
            sessionUserIdProvider.overrideWithValue(null),
            venuesProvider.overrideWith((_) async => [catalogVenue()]),
          ],
          child: MaterialApp(
            theme:
                brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  disableAnimations: true),
              child: child!,
            ),
            home: const ExploreScreen(),
          )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Бодит кафе'));
      await tester.pumpAndSettle();
      expect(find.byType(VenueInformationSheet), findsOneWidget);
      expect(find.text('Google Maps-д харах'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('fallback retry stays reachable on a short phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retried = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue(null),
          venuesProvider.overrideWith((_) async => [catalogVenue()]),
          venueCatalogStatusProvider.overrideWith((_) =>
              const VenueCatalogStatus(
                  communityUnavailable: true, supplementalCount: 1)),
          refreshVenueCatalogProvider.overrideWith((_) => () {
                retried++;
              }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  disableAnimations: true),
              child: child!),
          home: const ExploreScreen(),
        )));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Сервертэй холбогдож чадсангүй'), findsOneWidget);
    expect(find.text('Чиглэл авах'), findsNothing);
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(retried, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
