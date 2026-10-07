import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/feed/providers/reels_provider.dart';
import 'package:night_owl_ub/features/feed/providers/saved_provider.dart';
import 'package:night_owl_ub/features/feed/screens/reels_screen.dart';
import 'package:night_owl_ub/features/feed/widgets/story_video.dart';

Map<String, dynamic> _reel(String id) => {
      'id': id,
      'user_id': 'author-$id',
      'media_url': 'https://media.test/$id.mp4',
      'media_type': 'video',
      'caption': 'Caption for $id',
      'profiles': {'username': 'venue_$id'},
      'likes_count': 3,
      'comments_count': 1,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) reply;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    reply = (request) async => http.Response('[]', 200,
        headers: {'content-type': 'application/json'}, request: request);
    await Supabase.initialize(
        url: 'https://example.test',
        anonKey: 'test-only-key',
        debug: false,
        httpClient: MockClient((request) => reply(request)),
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false, localStorage: EmptyLocalStorage()));
  });
  tearDown(() async => Supabase.instance.dispose());

  Future<GoRouter> render(WidgetTester tester,
      {String selected = 'clip-2'}) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(initialLocation: '/reels?id=$selected', routes: [
      GoRoute(
          path: '/reels',
          builder: (_, state) =>
              ReelsScreen(initialReelId: state.uri.queryParameters['id'])),
      GoRoute(
          path: '/search',
          builder: (_, __) => const Scaffold(body: Text('Covered screen'))),
      GoRoute(
          path: '/reels/create',
          builder: (_, __) => const Scaffold(body: Text('Create screen'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      reelsProvider
          .overrideWith((_) async => List.generate(3, (i) => _reel('clip-$i'))),
      savedPostIdsProvider.overrideWith((_) async => <String>{}),
    ], child: MaterialApp.router(routerConfig: router)));
    // The selected page jumps after the async data frame; don't settle an
    // intentionally animated video screen's music-disc ticker.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router;
  }

  List<StoryVideoView> players(WidgetTester tester) => tester
      .widgetList<StoryVideoView>(
          find.byType(StoryVideoView, skipOffstage: false))
      .toList();

  testWidgets(
      'selected preview ID is the visible playing page, not the first reel',
      (tester) async {
    await render(tester);
    expect(tester.takeException(), isNull);
    expect(tester.widget<PageView>(find.byType(PageView)).controller?.page, 2);
    expect(
        players(tester)
            .where((video) => video.active)
            .map((video) => video.url),
        ['https://media.test/clip-2.mp4']);
    expect(find.text('Caption for clip-2').hitTestable(), findsOneWidget);
    expect(find.text('Caption for clip-0').hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'backgrounding and a covered route pause the active video then resume it',
      (tester) async {
    final router = await render(tester);
    expect(players(tester).where((video) => video.active), hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(players(tester).every((video) => !video.active), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/clip-2.mp4');

    // This invokes the viewer's own navigation, including its immediate pause
    // before the route transition has finished.
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    expect(players(tester), isNotEmpty);
    expect(players(tester).every((video) => !video.active), isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Covered screen'), findsOneWidget);
    expect(players(tester).every((video) => !video.active), isTrue);
    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/clip-2.mp4');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('selected clip outside the current list is fetched and shown',
      (tester) async {
    final requested = <String?>[];
    reply = (request) async {
      requested.add(request.url.queryParameters['id']);
      return http.Response(jsonEncode([_reel('older-clip')]), 200,
          headers: {'content-type': 'application/json'}, request: request);
    };
    await render(tester, selected: 'older-clip');
    expect(requested, contains('eq.older-clip'));
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/older-clip.mp4');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'unavailable selected clip never silently plays a different video',
      (tester) async {
    await render(tester, selected: 'deleted-clip');
    expect(find.text('Энэ бичлэг устгагдсан эсвэл харах боломжгүй байна.'),
        findsOneWidget);
    expect(players(tester), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'confirmed delete wins over a pending create-return refresh and resumes remaining video',
      (tester) async {
    const me = 'author-clip-2';
    final pendingFollows = Completer<http.Response>();
    http.Request? heldRequest;
    var holdRefresh = false;
    var deleted = false;
    reply = (request) async {
      dynamic body = [];
      if (request.url.path == '/auth/v1/token') {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({
              'sub': me,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            })))
            .replaceAll('=', '');
        body = {
          'access_token': 'fixture.$payload.fixture',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': me,
            'aud': 'authenticated',
            'created_at': '2026-10-05T00:00:00Z'
          },
        };
      } else if (request.url.path == '/rest/v1/venues') {
        body = [
          {'id': 'owned-venue'}
        ];
      } else if (request.url.path == '/rest/v1/follows' && holdRefresh) {
        heldRequest = request;
        return pendingFollows.future;
      } else if (request.url.path == '/rest/v1/posts' &&
          request.method == 'DELETE') {
        expect(request.url.queryParameters['id'], 'eq.clip-2');
        expect(request.url.queryParameters['user_id'], 'eq.$me');
        deleted = true;
        body = [
          {'id': 'clip-2'}
        ];
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'}, request: request);
    };
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-password');
    final router = await render(tester);
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/clip-2.mp4');
    await tester.tap(find.byIcon(Icons.add_box_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Create screen'), findsOneWidget);
    holdRefresh = true;
    router.pop();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(heldRequest, isNotNull,
        reason: 'Create return reload is waiting with a stale snapshot.');
    expect(players(tester).every((video) => !video.active), isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Create screen'), findsNothing);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Устгах'));
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(deleted, isTrue);
    expect(tester.widget<PageView>(find.byType(PageView)).controller?.page, 1);
    pendingFollows.complete(http.Response('[]', 200,
        headers: {'content-type': 'application/json'}, request: heldRequest));
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(players(tester).any((video) => video.url.endsWith('/clip-2.mp4')),
        isFalse);
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/clip-1.mp4',
        reason:
            'Invalidating a refresh must also release covered/loading state.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
