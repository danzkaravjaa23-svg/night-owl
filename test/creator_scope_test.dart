import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_fonts.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';
import 'package:night_owl_ub/features/feed/screens/creator_screen.dart';

const _owner = '10000000-0000-0000-0000-000000000001';
const _creator = '10000000-0000-0000-0000-000000000002';
const _post = '20000000-0000-4000-8000-000000000001';
final _viewer = StateProvider<String?>((ref) => _owner);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppFonts.configure();
  var readable = true;
  Completer<http.Response>? oldPage;
  var capturePage = false;
  late ProviderContainer container;
  http.Response response(Object data) => http.Response(jsonEncode(data), 200,
      headers: {'content-type': 'application/json'});
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://fixture.test',
        anonKey: 'public-fixture-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          final raw = await (() async {
            final path = request.url.path;
            if (path == '/rest/v1/profiles') {
              return response([
                {
                  'id': _creator,
                  'username': 'creator_fixture',
                  'full_name': 'Creator',
                  'bio': 'public identity',
                  'followers_count': 1
                }
              ]);
            }
            if (path == '/rest/v1/posts') {
              if (capturePage) {
                capturePage = false;
                return oldPage!.future;
              }
              return response(readable
                  ? [
                      {
                        'id': _post,
                        'media_url': null,
                        'media_type': 'image',
                        'likes_count': 1,
                        'created_at': '2026-11-03T00:00:00Z'
                      }
                    ]
                  : []);
            }
            if (path == '/rest/v1/rpc/get_relationship') {
              return response({
                'following': readable,
                'can_view': readable,
                'private': true
              });
            }
            return response([]);
          })();
          return http.Response.bytes(raw.bodyBytes, raw.statusCode,
              headers: raw.headers, request: request);
        }));
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    readable = true;
    capturePage = false;
    oldPage = null;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': _owner,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
        })))
        .replaceAll('=', '');
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'fixture.$payload.fixture',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': _owner,
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z'
      }
    }));
  });
  Future<void> flush(WidgetTester tester) async {
    // The singleton SDK was initialized outside FakeAsync. Drain its real
    // event queue without waiting for intentionally held HTTP responses.
    for (var step = 0; step < 12; step++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> render(WidgetTester tester, {bool settle = true}) async {
    container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(_viewer))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CreatorScreen(creatorId: _creator))));
    if (settle) {
      await flush(tester);
    } else {
      await tester.pump();
      await flush(tester);
    }
  }

  Future<void> logout(WidgetTester tester) async {
    readable = false;
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    container.read(_viewer.notifier).state = null;
    await flush(tester);
  }

  testWidgets('creator private grid clears after logout on the same route',
      (tester) async {
    await render(tester);
    expect(find.byType(CustomScrollView), findsOneWidget);
    final tile = find.byKey(const ValueKey('creator-post-$_post'));
    await tester.scrollUntilVisible(tile, 250,
        scrollable: find.byType(Scrollable).first);
    expect(tile, findsOneWidget);
    await logout(tester);
    expect(tile, findsNothing);
    await tester.scrollUntilVisible(find.textContaining('Хувийн профайл'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Хувийн профайл'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'late private response cannot repopulate a logged-out creator view',
      (tester) async {
    capturePage = true;
    oldPage = Completer<http.Response>();
    await render(tester, settle: false);
    await logout(tester);
    oldPage!.complete(response([
      {
        'id': _post,
        'media_url': null,
        'media_type': 'image',
        'created_at': '2026-11-03T00:00:00Z'
      }
    ]));
    await flush(tester);
    expect(find.byKey(const ValueKey('creator-post-$_post')), findsNothing);
    await tester.scrollUntilVisible(find.textContaining('Хувийн профайл'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Хувийн профайл'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('relationship revocation invalidates loaded creator content',
      (tester) async {
    await render(tester);
    expect(find.byType(CustomScrollView), findsOneWidget);
    final tile = find.byKey(const ValueKey('creator-post-$_post'));
    await tester.scrollUntilVisible(tile, 250,
        scrollable: find.byType(Scrollable).first);
    expect(tile, findsOneWidget);
    readable = false;
    container.read(socialVersionProvider.notifier).state++;
    await flush(tester);
    expect(tile, findsNothing);
    await tester.scrollUntilVisible(find.textContaining('Хувийн профайл'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Хувийн профайл'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
