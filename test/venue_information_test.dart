import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/map/screens/explore_screen.dart';
import 'package:night_owl_ub/features/map/screens/map_screen.dart';
import 'package:night_owl_ub/features/map/screens/venue_reviews_screen.dart';
import 'package:night_owl_ub/features/map/widgets/venue_information_sheet.dart';
import 'package:night_owl_ub/models/venue.dart';

/// Drag-handle shaped boxes inside the open sheet: 4 px tall, 30-48 px wide,
/// rounded. The theme's handle (36×4) counts, and so would a hand-drawn one
/// (DS-02: a sheet must show exactly one).
int sheetHandleCount(WidgetTester tester) => find
        .descendant(
            of: find.byType(BottomSheet),
            matching: find.byWidgetPredicate((widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).borderRadius != null))
        .evaluate()
        .where((element) {
      final box = element.renderObject;
      return box is RenderBox &&
          box.hasSize &&
          box.size.height == 4 &&
          box.size.width >= 30 &&
          box.size.width <= 48;
    }).length;

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
      // showAppSheet: the theme's handle only, no hand-drawn second one.
      expect(sheetHandleCount(tester), 1);
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
    await tester.tap(find.descendant(
        of: find.byType(MapScreen), matching: find.text('Дахин оролдох')));
    await tester.pumpAndSettle();
    expect(retried, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // The venue page's reviews sheet is a root sheet (showAppSheet). A SnackBar
  // shown while it is open would be painted UNDER it, so errors stay inside
  // the sheet and a successful send closes the sheet before confirming.
  group('venue reviews sheet', () {
    const account = '10000000-0000-4000-8000-000000000003';
    const venueId = '20000000-0000-4000-8000-000000000003';
    late http.Client transport;
    final writes = <http.Request>[];

    http.Response json(http.Request request, Object? body) => http.Response(
        jsonEncode(body), 200,
        request: request, headers: {'content-type': 'application/json'});

    Future<void> connect({required bool signedIn}) async {
      writes.clear();
      transport = MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          final payload = base64Url
              .encode(utf8.encode(jsonEncode({
                'sub': account,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              })))
              .replaceAll('=', '');
          return json(request, {
            'access_token': 'fixture.$payload.fixture',
            'refresh_token': 'fixture-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': account,
              'aud': 'authenticated',
              'created_at': '2026-11-03T00:00:00Z',
            },
          });
        }
        if (request.method != 'GET') {
          writes.add(request);
          return http.Response('', 201, request: request);
        }
        if (request.url.path.endsWith('/venues')) {
          return json(request, [
            {
              'id': venueId,
              'name': 'Fixture lounge',
              'venue_type': 'lounge',
              'district': 'Сүхбаатар',
              'rating': 0,
              'review_count': 0,
            }
          ]);
        }
        return json(request, []);
      });
      await Supabase.initialize(
          url: 'https://venue-reviews.example.test',
          anonKey: 'fixture-public-key',
          debug: false,
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false,
              detectSessionInUri: false,
              localStorage: EmptyLocalStorage()),
          httpClient: transport);
      if (signedIn) {
        await Supabase.instance.client.auth.signInWithPassword(
            email: 'fixture@example.test', password: 'fixture-password');
      }
    }

    tearDown(() async {
      await Supabase.instance.dispose();
      transport.close();
    });

    /// Opens "Үнэлгээ", picks one star and presses "Илгээх".
    Future<void> rateOneStar(WidgetTester tester,
        {required bool signedIn}) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            sessionUserIdProvider.overrideWithValue(signedIn ? account : null),
          ],
          child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                  data:
                      MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: child!),
              home: const VenueDetailScreen(venueId: venueId))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Үнэлгээ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Үнэлгээ'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(sheetHandleCount(tester), 1);
      await tester.tap(find
          .descendant(
              of: find.byType(BottomSheet),
              matching: find.byIcon(Icons.star_border_rounded))
          .first);
      await tester.pump();
      await tester.ensureVisible(find.text('Илгээх'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Илгээх'));
      await tester.pumpAndSettle();
    }

    group('signed out', () {
      setUp(() => connect(signedIn: false));

      testWidgets('the error is shown inside the open sheet, not under it',
          (tester) async {
        await rateOneStar(tester, signedIn: false);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(BottomSheet),
                matching: find.text('Нэвтэрнэ үү')),
            findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    });

    group('signed in', () {
      setUp(() => connect(signedIn: true));

      testWidgets('a sent review closes the sheet, then the page confirms',
          (tester) async {
        await rateOneStar(tester, signedIn: true);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Үнэлгээ илгээгдлээ'), findsOneWidget);
        final review = writes
            .where((request) => request.url.path.endsWith('/venue_reviews'))
            .single;
        expect(review.body, contains('"rating":1'));
        // Let the confirmation time out before the tree is removed.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
