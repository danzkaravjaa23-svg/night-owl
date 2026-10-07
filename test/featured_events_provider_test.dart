import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/events/providers/featured_events_provider.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';

void main() {
  late SupabaseClient client;
  late EventFeatureService service;
  late List<http.Request> requests;
  late http.Response response;
  const headers = {'content-type': 'application/json'};

  setUp(() {
    requests = [];
    response = http.Response('[]', 200, headers: headers);
    client = SupabaseClient(
      'https://example.test',
      'fixture-public-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(response.body, response.statusCode,
            headers: response.headers, request: request);
      }),
    );
    service = EventFeatureService(client: client);
  });
  tearDown(() => client.dispose());

  test('public provider uses curated RPC and preserves server ordering',
      () async {
    response = http.Response(
      jsonEncode([
        {
          'id': 'second-by-time-but-featured-first',
          'title': 'Night Owl сонголт',
          'starts_at': '2026-10-10T12:00:00Z',
          'venue_name': 'Fixture venue',
          'organizer_name': 'fixture-organizer',
          'price': 0,
          'attendee_count': 7,
        },
        {
          'id': 'first-by-time',
          'title': 'Acoustic night',
          'starts_at': '2026-10-09T12:00:00Z',
        },
      ]),
      200,
      headers: headers,
    );
    final container = ProviderContainer(overrides: [
      eventFeatureServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    final events = await container.read(featuredEventsProvider.future);
    expect(events.map((event) => event.id),
        ['second-by-time-but-featured-first', 'first-by-time']);
    expect(events.first.venueName, 'Fixture venue');
    expect(events.first.attendeeCount, 7);
    expect(events.last.price, 0);
    expect(events.last.venueName, isNull);
    expect(requests.single.url.path, '/rest/v1/rpc/get_featured_events');
    expect(() => events.clear(), throwsUnsupportedError);
  });

  test('empty curated selection stays empty without ordinary-event fallback',
      () async {
    expect(await service.loadFeatured(), isEmpty);
    expect(requests, hasLength(1));
  });

  test('only absent RPC maps to explicit migration-unavailable state',
      () async {
    response = http.Response(
        '{"code":"PGRST202","message":"Function not in schema cache"}', 404,
        headers: headers);
    await expectLater(service.loadFeatured(),
        throwsA(isA<FeatureEventsUnavailableException>()));
    response = http.Response(
        '{"code":"42501","message":"Not an active administrator"}', 403,
        headers: headers);
    await expectLater(
        service.loadSelections(),
        throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', '42501')));
    expect(requests, hasLength(2));
  });

  test('admin provider returns event IDs and order from guarded RPC', () async {
    response = http.Response('[{"event_id":"fixture-event","rank":12}]', 200,
        headers: headers);
    final container = ProviderContainer(overrides: [
      eventFeatureServiceProvider.overrideWithValue(service),
      sessionUserIdProvider.overrideWithValue('fixture-admin'),
    ]);
    addTearDown(container.dispose);
    final selected = await container.read(adminFeaturedEventsProvider.future);
    expect(selected.single.eventId, 'fixture-event');
    expect(selected.single.rank, 12);
    expect(requests.single.url.path, '/rest/v1/rpc/get_admin_featured_events');
  });

  test('admin selections reload on account switch and clear after sign-out',
      () async {
    final account = StateProvider<String?>((ref) => 'fixture-admin');
    final container = ProviderContainer(overrides: [
      eventFeatureServiceProvider.overrideWithValue(service),
      sessionUserIdProvider.overrideWith((ref) => ref.watch(account)),
    ]);
    addTearDown(container.dispose);
    response = http.Response('[{"event_id":"fixture-event","rank":0}]', 200,
        headers: headers);
    expect(
        await container.read(adminFeaturedEventsProvider.future), hasLength(1));
    response = http.Response(
        '{"code":"42501","message":"Permission denied"}', 403,
        headers: headers);
    container.read(account.notifier).state = 'fixture-non-admin';
    await expectLater(container.read(adminFeaturedEventsProvider.future),
        throwsA(isA<PostgrestException>()));
    container.read(account.notifier).state = null;
    expect(await container.read(adminFeaturedEventsProvider.future), isEmpty);
    expect(requests, hasLength(2),
        reason: 'Signed-out users need no admin RPC.');
  });

  test('selection and removal send guarded commands and propagate denial',
      () async {
    response = http.Response('', 204);
    await service.setFeatured('fixture-event', featured: true, rank: 3);
    await service.setFeatured('fixture-event', featured: false);
    expect(requests.map((request) => request.url.path),
        everyElement('/rest/v1/rpc/set_featured_event'));
    expect(jsonDecode(requests.first.body), {
      'p_event_id': 'fixture-event',
      'p_featured': true,
      'p_rank': 3,
    });
    expect(jsonDecode(requests.last.body)['p_featured'], isFalse);
    response = http.Response(
        '{"code":"42501","message":"Permission denied"}', 403,
        headers: headers);
    await expectLater(service.setFeatured('fixture-event', featured: true),
        throwsA(isA<PostgrestException>()));
    expect(requests, hasLength(3),
        reason: 'No direct-table mutation fallback.');
  });

  test('invalid ranks fail before sending a mutation', () async {
    for (final rank in [-1, 10000]) {
      await expectLater(
        service.setFeatured('fixture-event', featured: true, rank: rank),
        throwsRangeError,
      );
    }
    expect(requests, isEmpty);
  });
}
