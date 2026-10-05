import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/feed/providers/feed_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) reply;
  const headers = {'content-type': 'application/json'};
  final fullPage = jsonEncode([
    for (var i = 0; i < 20; i++)
      {
        'id': 'fixture-post-$i',
        'user_id': 'fixture-author',
        'created_at': '2026-10-01T01:00:00Z',
        'caption': 'Fixture $i',
      }
  ]);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    reply = (request) async => http.Response(fullPage, 200, headers: headers);
    await Supabase.initialize(
        url: 'https://example.test',
        anonKey: 'test-only-anon-key',
        debug: false,
        httpClient: MockClient((request) async {
          final response = await reply(request);
          return http.Response(response.body, response.statusCode,
              headers: response.headers, request: request);
        }),
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()));
  });
  tearDown(() async => Supabase.instance.dispose());

  for (final failing in [false, true]) {
    test(
        'pagination ${failing ? 'failure' : 'exhaustion'} stops factual request state',
        () async {
      final feed = FeedNotifier();
      await feed.loadFeed(refresh: true);
      expect(feed.state.hasValue, isTrue, reason: feed.state.toString());
      expect(feed.hasMore.value, isTrue);
      expect(feed.isFetching.value, isFalse,
          reason: 'A possible next page is not an active network request.');
      final response = Completer<http.Response>();
      reply = (_) => response.future;
      final changes = <bool>[];
      feed.isFetching.addListener(() => changes.add(feed.isFetching.value));
      final pending = feed.loadFeed();
      expect(feed.isFetching.value, isTrue);
      response.complete(http.Response(
          failing ? '{"code":"XX000","message":"Fixture failed"}' : '[]',
          failing ? 400 : 200,
          headers: headers));
      await pending;
      expect(changes, [true, false]);
      expect(feed.isFetching.value, isFalse);
      expect(feed.pageError.value, failing);
      expect(feed.state.value, hasLength(20),
          reason: 'Loaded posts remain on a later failure.');
      expect(feed.hasMore.value, failing);
      reply = (_) async => http.Response('[]', 200, headers: headers);
      await feed.loadFeed(refresh: true);
      expect(feed.isFetching.value, isFalse);
      expect(feed.pageError.value, isFalse);
      expect(feed.hasMore.value, isFalse);
      final count = changes.length;
      await feed.loadFeed();
      expect(changes.length, count,
          reason: 'Exhausted pagination sends no request.');
      feed.dispose();
    });
  }

  test(
      'initial failure and retry both release loading, including disposal in flight',
      () async {
    reply = (_) async => http.Response(
        '{"code":"42501","message":"Fixture rejected"}', 403,
        headers: headers);
    final feed = FeedNotifier();
    await feed.loadFeed(refresh: true);
    expect(feed.state.hasError, isTrue);
    expect(feed.isFetching.value, isFalse);
    final response = Completer<http.Response>();
    reply = (_) => response.future;
    final pending = feed.loadFeed(refresh: true);
    expect(feed.isFetching.value, isTrue);
    feed.dispose();
    response.complete(http.Response('[]', 200, headers: headers));
    await pending; // Disposed notifier and listeners must never be updated.
  });
}
