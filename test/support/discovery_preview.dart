// Isolated UI fixture. Never authenticates against or changes the live backend.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/main.dart' show NightOwlApp;

const fixtureUser = '10000000-0000-0000-0000-000000000001';
const fixturePeer = '10000000-0000-0000-0000-000000000002';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final source = jsonDecode(await rootBundle
      .loadString('assets/data/ulaanbaatar_osm_venues.json')) as Map;
  final places = (source['venues'] as List)
      .map((v) => {
            ...v as Map<String, dynamic>,
            'ref': v['id'],
            'venue_id': null,
            'hours': v['source_opening_hours']
          })
      .toList();
  final privacy = <String, dynamic>{
    'is_private': false,
    'dm_policy': 'requests'
  };
  final saves = <String>{};
  final collections = <Map<String, dynamic>>[];
  var pending = true;
  var dmState = 'incoming';
  final profile = <String, dynamic>{
    'id': fixtureUser,
    'username': 'fixture_owner',
    'full_name': 'Шалгалтын профайл',
    'bio': 'Локал шалгалтын өгөгдөл',
    'avatar_url': 'nightowl://avatar/owl-young-woman',
    'is_admin': true,
    'is_banned': false,
    'is_verified': false,
    'created_at': '2026-10-16T00:00:00Z',
    'interests': ['Jazz']
  };
  http.Response result(http.Request r, Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'}, request: r);
  List<Map<String, dynamic>> matchRows(
      http.Request r, List<Map<String, dynamic>> rows) {
    var matches = rows;
    for (final key in ['id', 'ref', 'user_id', 'venue_ref']) {
      final value = r.url.queryParameters[key];
      if (value != null && value.startsWith('eq.')) {
        matches =
            matches.where((row) => row[key] == value.substring(3)).toList();
      }
    }
    if (r.url.queryParameters['reviewed_at'] != null) matches = [];
    final name = r.url.queryParameters['name'];
    if (name != null && name.startsWith('ilike.')) {
      matches = matches
          .where((row) => '${row['name']}'
              .toLowerCase()
              .contains(name.substring(6).replaceAll('%', '').toLowerCase()))
          .toList();
    }
    return matches;
  }

  await Supabase.initialize(
      url: 'https://fixture.test',
      anonKey: 'fixture-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage()),
      httpClient: MockClient((r) async {
        final path = r.url.path;
        if (path == '/auth/v1/token') {
          final payload = base64Url
              .encode(utf8.encode(jsonEncode({
                'sub': fixtureUser,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
              })))
              .replaceAll('=', '');
          return result(r, {
            'access_token': 'fixture.$payload.fixture',
            'refresh_token': 'fixture-refresh',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': fixtureUser,
              'aud': 'authenticated',
              'email': 'fixture@example.test',
              'created_at': profile['created_at'],
              'user_metadata': {'setup_complete': true}
            }
          });
        }
        if (path.endsWith('/get_relationship')) {
          return result(r, {
            'following': false,
            'requested': false,
            'private': false,
            'can_view': true,
            'dm_state': dmState,
            'blocked': false
          });
        }
        if (path.endsWith('/discover_creators')) {
          return result(r, [
            {
              ...profile,
              'id': fixturePeer,
              'username': 'fixture_creator',
              'full_name': 'Туршилтын creator',
              'posts_count': 3,
              'followers_count': 0
            }
          ]);
        }
        if (path.endsWith('/get_pilot_overview')) {
          return result(r, {
            'users': 0,
            'creator_count': 0,
            'venues': 0,
            'content': 0,
            'activation_eligible': 0,
            'activated': 0,
            'first_day_followed': 0,
            'first_day_saved': 0,
            'd7_eligible': 0,
            'd7_returned': 0,
            'repeat_creators': 0,
            'directions': 0,
            'creators': [],
            'participants': [],
            'places': [],
            'posts': []
          });
        }
        if (path.endsWith('/search_pilot_candidates')) return result(r, []);
        if (path.endsWith('/respond_message_request')) {
          dmState = (jsonDecode(r.body) as Map)['p_accept'] == true
              ? 'accepted'
              : 'new';
          return result(r, null);
        }
        if (path.endsWith('/import_venue_saves')) {
          saves.addAll(
              ((jsonDecode(r.body) as Map)['p_refs'] as List).cast<String>());
          return result(r, saves.length);
        }
        if (path.endsWith('/respond_follow_request')) {
          pending = false;
          return result(r, null);
        }
        if (path.endsWith('/venue_saves')) {
          if (r.method == 'POST') {
            saves.add((jsonDecode(r.body) as Map)['venue_ref'] as String);
            return result(r, null, 201);
          }
          if (r.method == 'DELETE') {
            saves.remove(r.url.queryParameters['venue_ref']?.substring(3));
          }
          return result(r, saves.map((id) => {'venue_ref': id}).toList());
        }
        var rows = <Map<String, dynamic>>[];
        if (path.endsWith('/profiles')) {
          if (r.method == 'PATCH') {
            privacy
                .addAll(Map<String, dynamic>.from(jsonDecode(r.body) as Map));
          }
          rows = [
            {...profile, ...privacy},
            {
              ...profile,
              'id': fixturePeer,
              'username': 'fixture_creator',
              'full_name': 'Туршилтын creator',
              'is_admin': false
            },
          ];
        } else if (path.endsWith('/venue_catalog')) {
          rows = places;
        } else if (path.endsWith('/follow_requests')) {
          rows = pending
              ? [
                  {
                    'requester_id': fixturePeer,
                    'profiles': {
                      'id': fixturePeer,
                      'username': 'fixture_creator'
                    }
                  }
                ]
              : [];
        } else if (path.endsWith('/place_collections')) {
          if (r.method == 'POST') {
            collections.add({
              ...jsonDecode(r.body) as Map<String, dynamic>,
              'id': '40000000-0000-0000-0000-000000000001',
              'collection_places': []
            });
          }
          rows = collections;
        } else if (path.endsWith('/collection_places') && r.method == 'POST') {
          final body = jsonDecode(r.body) as Map;
          for (final collection
              in collections.where((c) => c['id'] == body['collection_id'])) {
            (collection['collection_places'] as List).add({
              ...body,
              'venue_catalog':
                  places.firstWhere((p) => p['ref'] == body['venue_ref'])
            });
          }
        }
        rows = matchRows(r, rows);
        if (r.headers['accept']?.contains('vnd.pgrst.object') == true) {
          return result(r, rows.isEmpty ? null : rows.first);
        }
        return result(r, rows);
      }));
  await Supabase.instance.client.auth.signInWithPassword(
      email: 'fixture@example.test', password: 'fixture-password');
  runApp(const ProviderScope(child: NightOwlApp()));
}
