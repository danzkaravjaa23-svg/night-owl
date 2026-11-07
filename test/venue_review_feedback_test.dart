import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/map/screens/venue_reviews_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = '10000000-0000-4000-8000-000000000001';
  const venueId = '30000000-0000-4000-8000-000000000001';
  late List<http.Request> requests;
  late Object? Function(http.Request) upsertBody;
  late http.Client transport;

  http.Response json(http.Request request, Object? body) =>
      http.Response(jsonEncode(body), 200,
          request: request, headers: {'content-type': 'application/json'});

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    requests = [];
    upsertBody = (_) => {'moderation_status': 'approved'};
    transport = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/v1/token') {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({
              'sub': owner,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            })))
            .replaceAll('=', '');
        return json(request, {
          'access_token': 'fixture.$payload.fixture',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': owner,
            'aud': 'authenticated',
            'created_at': '2026-11-03T00:00:00Z',
          },
        });
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/venue_reviews')) {
        return json(request, upsertBody(request));
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
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'owner@example.test', password: 'fixture-password');
    requests.clear();
  });

  tearDown(() async {
    await Supabase.instance.dispose();
    transport.close();
  });

  Future<void> submitReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: VenueReviewsSheet(venueId: venueId))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_border_rounded).last);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Great music');
    await tester.tap(find.text('Илгээх'));
    await tester.pumpAndSettle();
  }

  for (final (saved, message) in <(Object?, String)>[
    ({'moderation_status': 'approved'}, 'Үнэлгээ нийтлэгдлээ'),
    (
      {'moderation_status': 'pending'},
      'Шалгалтад байна. Модератор баталсны дараа бусдад харагдана.'
    ),
    (<String, Object>{}, 'Хадгалагдлаа'),
  ]) {
    testWidgets('venue review reports the saved state $saved truthfully',
        (tester) async {
      upsertBody = (_) => saved;
      await submitReview(tester);
      final writes = requests
          .where((r) =>
              r.method == 'POST' && r.url.path.endsWith('/venue_reviews'))
          .toList();
      expect(writes, hasLength(1));
      // The upsert must ask for the saved row's status, or every approved
      // review would fall back to the neutral 'Хадгалагдлаа'.
      expect(writes.single.url.queryParameters['select'], 'moderation_status');
      final body = jsonDecode(writes.single.body) as Map;
      expect(body['venue_id'], venueId);
      expect(body['user_id'], owner);
      expect(body['rating'], 5);
      expect(body['comment'], 'Great music');
      expect(find.text(message), findsOneWidget);
      if (message != 'Үнэлгээ нийтлэгдлээ') {
        expect(find.text('Үнэлгээ нийтлэгдлээ'), findsNothing);
      }
      expect(find.textContaining('Илгээж чадсангүй'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
