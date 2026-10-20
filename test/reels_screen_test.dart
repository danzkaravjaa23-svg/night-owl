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
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';

Map<String, dynamic> _authSession(String me) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({
        'sub': me,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      })))
      .replaceAll('=', '');
  return {
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
}

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
      {String selected = 'clip-2',
      Future<List<Map<String, dynamic>>> Function()? following,
      Future<List<Map<String, dynamic>>> Function()? all,
      Set<String> saved = const {},
      Widget? coveredPage}) async {
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
          builder: (_, __) =>
              coveredPage ?? const Scaffold(body: Text('Covered screen'))),
      GoRoute(
          path: '/reels/create',
          builder: (_, __) => const Scaffold(body: Text('Create screen'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      reelsProvider.overrideWith((_) =>
          all?.call() ??
          Future.value(List.generate(3, (i) => _reel('clip-$i')))),
      followingReelsProvider.overrideWith(
          (_) => following?.call() ?? Future.value([_reel('followed-old')])),
      savedPostIdsProvider.overrideWith((_) async => saved),
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
      'Following shows its server results without injecting a shared ID',
      (tester) async {
    await render(tester);
    await tester.tap(find.text('Дагадаг'));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/followed-old.mp4');
    expect(find.text('Caption for followed-old').hitTestable(), findsOneWidget);
    expect(players(tester).any((video) => video.url.endsWith('clip-2.mp4')),
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a late Following response cannot replace the For You tab',
      (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    await render(tester, following: () => pending.future);
    await tester.tap(find.text('Дагадаг'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(players(tester), isEmpty);
    await tester.tap(find.text('Танд'));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    pending.complete([_reel('late-followed')]);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/clip-2.mp4');
    expect(
        players(tester).any((video) => video.url.endsWith('late-followed.mp4')),
        isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Following retry keeps its tab and never shows unrelated clips',
      (tester) async {
    var attempts = 0;
    await render(tester, following: () async {
      if (++attempts == 1) throw StateError('Offline');
      return [_reel('retried-followed')];
    });
    await tester.tap(find.text('Дагадаг'));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Ачаалж чадсангүй'), findsOneWidget);
    expect(players(tester), isEmpty);
    await tester.tap(find.text('Дахин оролдох'));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(attempts, 2);
    expect(players(tester).where((video) => video.active).single.url,
        'https://media.test/retried-followed.mp4');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('returning after a privacy change rechecks cached reels',
      (tester) async {
    var restricted = false;
    var loads = 0;
    await render(tester, all: () async {
      loads++;
      return restricted ? [] : List.generate(3, (i) => _reel('clip-$i'));
    },
        coveredPage: Consumer(
            builder: (context, ref, _) => Scaffold(
                  body: TextButton(
                      onPressed: () {
                        restricted = true;
                        ref.read(socialVersionProvider.notifier).state++;
                        context.pop();
                      },
                      child: const Text('Fixture privacy change')),
                )));
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Fixture privacy change'));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(loads, 2);
    expect(players(tester), isEmpty);
    expect(find.text('Энэ бичлэг устгагдсан эсвэл харах боломжгүй байна.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final denied in [false, true]) {
    testWidgets('Reel report reaches the server and preserves denial=$denied',
        (tester) async {
      final reported = <Map<String, dynamic>>[];
      final submitted = Completer<http.Response>();
      http.Request? reportRequest;
      reply = (request) async {
        if (request.url.path == '/auth/v1/token') {
          return http.Response(jsonEncode(_authSession('fixture-viewer')), 200,
              headers: {'content-type': 'application/json'}, request: request);
        }
        if (request.url.path == '/rest/v1/reports') {
          reportRequest = request;
          reported
              .add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
          return submitted.future;
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'}, request: request);
      };
      await Supabase.instance.client.auth.signInWithPassword(
          email: 'fixture@example.test', password: 'fixture-password');
      await render(tester);
      await tester.tap(find.byIcon(Icons.more_horiz).hitTestable());
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(players(tester).every((video) => !video.active), isTrue);
      await tester.tap(find.text('Мэдэгдэх'));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Юунд мэдээлэх вэ?'), findsOneWidget);
      expect(reported, isEmpty);
      await tester.tap(find.text('Спам / хуурамч'));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(reported, [
        {
          'reporter_id': 'fixture-viewer',
          'target_type': 'post',
          'target_id': 'clip-2',
          'reason': 'spam',
        }
      ]);
      expect(find.textContaining('Мэдээлэл хүлээн авлаа'), findsNothing);
      submitted.complete(denied
          ? http.Response('{"code":"42501","message":"Denied"}', 403,
              headers: {'content-type': 'application/json'},
              request: reportRequest)
          : http.Response('', 204, request: reportRequest));
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Initial progress toast lasts two seconds, then the server result.
      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.textContaining('Мэдэгдлийг хүлээн авлаа'), findsNothing);
      if (denied) {
        expect(find.textContaining('Энэ үйлдлийг хийх эрхгүй'), findsOneWidget);
      } else {
        expect(find.textContaining('Мэдээлэл хүлээн авлаа'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  for (final initiallySaved in [false, true]) {
    for (final denied in [false, true]) {
      testWidgets(
          'Reel save initially=$initiallySaved denied=$denied guards duplicate taps',
          (tester) async {
        final saved = {if (initiallySaved) 'clip-2'};
        final pending = Completer<http.Response>();
        http.Request? heldRequest;
        var writes = 0;
        reply = (request) async {
          if (request.url.path == '/auth/v1/token') {
            return http.Response(
                jsonEncode(_authSession('fixture-viewer')), 200,
                headers: {'content-type': 'application/json'},
                request: request);
          }
          if (request.url.path == '/rest/v1/saved_posts' &&
              request.method != 'GET') {
            writes++;
            heldRequest = request;
            final response = await pending.future;
            if (!denied) {
              initiallySaved ? saved.remove('clip-2') : saved.add('clip-2');
            }
            return response;
          }
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'}, request: request);
        };
        await Supabase.instance.client.auth.signInWithPassword(
            email: 'fixture@example.test', password: 'fixture-password');
        await render(tester, saved: saved);
        await tester.tap(find
            .byIcon(initiallySaved ? Icons.bookmark : Icons.bookmark_border)
            .hitTestable());
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find
            .byIcon(initiallySaved ? Icons.bookmark_border : Icons.bookmark)
            .hitTestable());
        await tester.pump();
        expect(writes, 1);
        expect(heldRequest!.method, initiallySaved ? 'DELETE' : 'POST');
        if (initiallySaved) {
          expect(heldRequest!.url.queryParameters['post_id'], 'eq.clip-2');
          expect(
              heldRequest!.url.queryParameters['user_id'], 'eq.fixture-viewer');
        } else {
          expect(jsonDecode(heldRequest!.body),
              {'user_id': 'fixture-viewer', 'post_id': 'clip-2'});
        }
        expect(find.text('Хадгаллаа'), findsNothing);
        pending.complete(denied
            ? http.Response('{"code":"42501","message":"Denied"}', 403,
                headers: {'content-type': 'application/json'},
                request: heldRequest)
            : http.Response('', 204, request: heldRequest));
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final expectedSaved = denied ? initiallySaved : !initiallySaved;
        expect(
            find
                .byIcon(expectedSaved ? Icons.bookmark : Icons.bookmark_border)
                .hitTestable(),
            findsOneWidget);
        if (denied) {
          expect(find.text('Хадгаллаа'), findsNothing);
          expect(
              find.text(initiallySaved
                  ? 'Хадгалснаа хасаж чадсангүй'
                  : 'Хадгалж чадсангүй. Дахин оролдоно уу'),
              findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }

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
        body = _authSession(me);
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
