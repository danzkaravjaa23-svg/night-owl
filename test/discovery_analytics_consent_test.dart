import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/constants/community_rules.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';

void main() {
  test('adult declaration and current community agreement are both required',
      () {
    for (final metadata in <Map<String, dynamic>?>[
      null,
      {},
      {'adult_confirmed': true},
      {
        'adult_confirmed': 'true',
        'community_rules_version': CommunityRules.version
      },
      {
        'adult_confirmed': false,
        'community_rules_version': CommunityRules.version
      },
      {'adult_confirmed': true, 'community_rules_version': 'old'},
    ]) {
      expect(CommunityRules.isAccepted(metadata), isFalse);
    }
    final now = DateTime.utc(2026, 11, 3, 10);
    final acceptance = CommunityRules.acceptance(now);
    expect(CommunityRules.isAccepted(acceptance), isTrue);
    expect(acceptance['community_rules_accepted_at'], now.toIso8601String());
    expect(acceptance.containsKey('discovery_analytics_consent'), isFalse);
  });

  late SupabaseClient client;
  late List<http.Request> requests;
  var status = 200;
  setUp(() {
    requests = [];
    status = 200;
    client = SupabaseClient(
        'https://fixture.example.test', 'fixture-public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response(
          status == 200 ? 'null' : '{"message":"offline","code":"XX000"}',
          status,
          headers: {'content-type': 'application/json'});
    }));
  });
  tearDown(() => client.dispose());

  Future<void> session(Object? consent) async {
    final claims = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': 'fixture-owner',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        })))
        .replaceAll('=', '');
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'fixture.$claims.fixture',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'fixture-owner',
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z',
        'user_metadata': {
          if (consent != null) 'discovery_analytics_consent': consent,
        },
      },
    }));
  }

  test('anonymous activity never starts a statistics request', () async {
    await DiscoveryService(client: client).activity('session');
    expect(requests, isEmpty);
  });

  test('missing, false and malformed consent never start a request', () async {
    for (final consent in [null, false, 'true', 1]) {
      await session(consent);
      await DiscoveryService(client: client).activity('session');
    }
    expect(requests, isEmpty);
  });

  test('explicit opt-in records activity; withdrawal stops the next request',
      () async {
    final service = DiscoveryService(client: client);
    await session(true);
    await service.activity('profile_view', target: 'fixture-creator');
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/rest/v1/rpc/record_discovery_activity');
    expect(jsonDecode(requests.single.body), {
      'p_event': 'profile_view',
      'p_target': 'fixture-creator',
    });
    await session(false);
    await service.activity('session');
    expect(requests, hasLength(1));
  });

  test('statistics failure cannot interrupt app use', () async {
    await session(true);
    status = 503;
    await DiscoveryService(client: client).activity('session');
    expect(requests, hasLength(1));
  });
}
