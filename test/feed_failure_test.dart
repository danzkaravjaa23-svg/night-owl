import 'dart:async';
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    reply = (request) async => http.Response('[]', 200, headers: {'content-type': 'application/json'}, request: request);
    await Supabase.initialize(url: 'https://example.test', anonKey: 'test-only-anon-key',
      debug: false, httpClient: MockClient((request) => reply(request)),
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false, localStorage: EmptyLocalStorage()));
  });
  tearDown(() async => Supabase.instance.dispose());
  test('first backend failure becomes a retryable error instead of an endless spinner', () async {
    reply = (request) async => http.Response('{"code":"XX000","message":"test backend unavailable"}', 400,
      headers: {'content-type': 'application/json'}, request: request);
    final feed = FeedNotifier();
    await feed.loadFeed(refresh: true);
    expect(feed.state.hasError, isTrue);
    expect(feed.state.isLoading, isFalse);
    reply = (request) async => http.Response('[]', 200, headers: {'content-type': 'application/json'}, request: request);
    await feed.loadFeed(refresh: true);
    expect(feed.state.hasValue, isTrue, reason: feed.state.toString());
    expect(feed.state.value, isEmpty);
    feed.dispose();
  });
  for (final fails in [false, true]) {
    test('a late ${fails ? 'error' : 'result'} cannot update a disposed account feed', () async {
      final response = Completer<http.Response>();
      reply = (request) async {
        final result = await response.future;
        return http.Response(result.body, result.statusCode, headers: result.headers, request: request);
      };
      final feed = FeedNotifier();
      final pending = feed.loadFeed(refresh: true);
      feed.dispose();
      response.complete(http.Response(fails ? '{"code":"XX000","message":"test error"}' : '[]',
        fails ? 400 : 200, headers: {'content-type': 'application/json'}));
      await pending;
      // The test fails on any disposed StateNotifier/ValueNotifier exception.
    });
  }
  test('an unauthenticated caption edit cannot report success', () async {
    final feed = FeedNotifier();
    await feed.loadFeed(refresh: true);
    await expectLater(feed.editCaption('post', 'caption'), throwsStateError);
    feed.dispose();
  });
}
