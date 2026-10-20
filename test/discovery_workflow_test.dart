import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/services/media_access.dart';
import 'package:night_owl_ub/core/constants/app_constants.dart';
import 'package:night_owl_ub/core/widgets/authorized_media.dart';
import 'package:night_owl_ub/core/utils/auth_return.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';
import 'package:night_owl_ub/features/discovery/screens/privacy_screen.dart';
import 'package:night_owl_ub/features/discovery/screens/pilot_screen.dart';
import 'package:night_owl_ub/features/discovery/screens/discovery_screen.dart';
import 'package:night_owl_ub/features/discovery/screens/collections_screen.dart';
import 'package:night_owl_ub/features/discovery/screens/place_screen.dart';
import 'package:night_owl_ub/features/discovery/screens/review_place_screen.dart';
import 'package:night_owl_ub/features/feed/providers/feed_provider.dart';
import 'package:night_owl_ub/features/feed/providers/comment_provider.dart';
import 'package:night_owl_ub/features/feed/providers/stories_provider.dart';
import 'package:night_owl_ub/features/feed/providers/saved_provider.dart';
import 'package:night_owl_ub/features/feed/providers/reels_provider.dart';
import 'package:night_owl_ub/features/events/providers/event_provider.dart';
import 'package:night_owl_ub/features/notifications/providers/notification_provider.dart';
import 'package:night_owl_ub/features/feed/screens/feed_screen.dart';
import 'package:night_owl_ub/features/feed/screens/post_detail_screen.dart';
import 'package:night_owl_ub/features/feed/screens/saved_posts_screen.dart';
import 'package:night_owl_ub/features/feed/screens/reels_screen.dart';
import 'package:night_owl_ub/features/map/providers/venue_bookmarks_provider.dart';
import 'package:night_owl_ub/models/post.dart';
import 'package:night_owl_ub/models/comment.dart';
import 'package:night_owl_ub/features/dm/screens/dm_thread_screen.dart';

const me = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';

class _FixtureFeed extends FeedNotifier {
  final Post post;
  _FixtureFeed(this.post);
  @override
  Future<void> loadFeed({bool refresh = false}) async {
    state = AsyncValue.data([post]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late DiscoveryService service;
  http.Response json(http.Request request, Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status,
          headers: {'content-type': 'application/json'}, request: request);
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    requests = [];
    respond = (request) async => json(request, []);
    await Supabase.initialize(
        url: 'https://example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/auth/v1/token') {
            final payload = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': me,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
                })))
                .replaceAll('=', '');
            return json(request, {
              'access_token': 'fixture.$payload.fixture',
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': me,
                'aud': 'authenticated',
                'created_at': '2026-10-16T00:00:00Z'
              }
            });
          }
          return respond(request);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-password');
    requests.clear();
    service = DiscoveryService();
  });
  tearDown(() async {
    AuthReturn.clear();
    await Supabase.instance.dispose();
  });

  ProviderContainer savedScope({StateProvider<String?>? account}) {
    final container = ProviderContainer(overrides: [
      if (account == null)
        sessionUserIdProvider.overrideWithValue(me)
      else
        sessionUserIdProvider.overrideWith((ref) => ref.watch(account)),
      currentProfileProvider.overrideWith((ref) async => null),
      feedProvider.overrideWith((ref) => _FixtureFeed(Post(
          id: 'fixture-post',
          userId: other,
          createdAt: DateTime.utc(2026, 10, 16)))),
      commentsProvider('fixture-post').overrideWith((ref) => Stream.value([])),
      storiesProvider.overrideWith((ref) async => []),
      feedFollowingIdsProvider.overrideWith((ref) async => {}),
      upcomingEventsProvider.overrideWith((ref) async => []),
      unreadNotifCountProvider.overrideWithValue(0),
      reelsProvider.overrideWith((ref) async => [
            {
              'id': 'fixture-post',
              'user_id': other,
              'media_type': 'video',
              'media_url': 'https://fixture.test/clip.mp4',
              'profiles': {'username': 'fixture_creator'},
            }
          ]),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> saveFrames(WidgetTester tester) async {
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> renderSavedSurface(
      WidgetTester tester, ProviderContainer container, String surface) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Widget app;
    if (surface == 'reels') {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const ReelsScreen()),
      ]);
      addTearDown(router.dispose);
      app = MaterialApp.router(routerConfig: router);
    } else {
      app = MaterialApp(
          home: surface == 'feed'
              ? const FeedScreen()
              : const PostDetailScreen(postId: 'fixture-post'));
    }
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: app));
    await saveFrames(tester);
  }

  Finder savedButton(String surface, bool saved) => surface == 'feed'
      ? find.byTooltip(saved ? 'Хадгалснаас хасах' : 'Хадгалах')
      : find
          .byIcon(saved ? Icons.bookmark : Icons.bookmark_border)
          .hitTestable();

  http.Response savedOtherResponse(http.Request r) {
    if (r.url.path.endsWith('/posts')) {
      return json(r, {
        'id': 'fixture-post',
        'user_id': other,
        'created_at': '2026-10-16T00:00:00Z'
      });
    }
    if (r.url.path.endsWith('/profiles')) {
      return json(r, {'id': me, 'username': 'fixture_me'});
    }
    if (r.url.path.endsWith('/likes') &&
        r.headers['accept']?.contains('vnd.pgrst.object') == true) {
      return http.Response('null', 200,
          headers: {'content-type': 'application/json'}, request: r);
    }
    return json(r, []);
  }

  test('saved-ID read denial remains an error rather than an empty list',
      () async {
    respond = (r) async => json(r, {'code': '42501', 'message': 'Denied'}, 403);
    final container = savedScope();
    await expectLater(container.read(savedPostIdsProvider.future),
        throwsA(isA<PostgrestException>()));
    expect(container.read(savedPostIdsProvider).hasError, isTrue);
  });

  testWidgets(
      'saved-ID reads time out instead of leaving actions waiting forever',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? heldRequest;
    respond = (r) {
      heldRequest = r;
      return pending.future;
    };
    final container = savedScope();
    Object? failure;
    container.read(savedPostIdsProvider.future).then<void>((_) {},
        onError: (Object e, StackTrace _) {
      failure = e;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    final observed = failure;
    pending.complete(json(heldRequest!, []));
    await tester.pump();
    expect(observed, isA<TimeoutException>());
  });

  for (final surface in ['feed', 'detail', 'reels']) {
    testWidgets('$surface waits for saved state before choosing save or remove',
        (tester) async {
      final pending = Completer<http.Response>();
      http.Request? heldRequest;
      final writes = <http.Request>[];
      var reads = 0;
      var saved = true;
      respond = (r) async {
        if (r.url.path.endsWith('/saved_posts')) {
          if (r.method == 'GET') {
            if (++reads == 1) {
              heldRequest = r;
              return pending.future;
            }
            return json(r, [
              if (saved) {'post_id': 'fixture-post'}
            ]);
          }
          writes.add(r);
          saved = r.method == 'POST';
          return http.Response('', 204, request: r);
        }
        return savedOtherResponse(r);
      };
      await renderSavedSurface(tester, savedScope(), surface);
      await tester.tap(savedButton(surface, false));
      await tester.pump();
      final beforeRead = writes.length;
      pending.complete(json(heldRequest!, [
        {'post_id': 'fixture-post'}
      ]));
      await saveFrames(tester);
      expect(beforeRead, 0);
      expect(writes, hasLength(1));
      expect(writes.single.method, 'DELETE');
      expect(saved, isFalse);
      expect(savedButton(surface, false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$surface failed saved-state read cannot write and can retry',
        (tester) async {
      var fail = true;
      var saved = true;
      final writes = <http.Request>[];
      respond = (r) async {
        if (r.url.path.endsWith('/saved_posts')) {
          if (r.method == 'GET') {
            return fail
                ? json(r, {'code': 'XX000', 'message': 'Read failed'}, 400)
                : json(r, [
                    if (saved) {'post_id': 'fixture-post'}
                  ]);
          }
          writes.add(r);
          saved = r.method == 'POST';
          return http.Response('', 204, request: r);
        }
        return savedOtherResponse(r);
      };
      await renderSavedSurface(tester, savedScope(), surface);
      await tester.tap(savedButton(surface, false));
      await saveFrames(tester);
      expect(writes, isEmpty);
      expect(
          find.text('Хадгалсан төлөвийг шалгаж чадсангүй. Дахин оролдоорой.'),
          findsOneWidget);
      fail = false;
      await tester.tap(savedButton(surface, false));
      await saveFrames(tester);
      expect(writes, hasLength(1));
      expect(writes.single.method, 'DELETE');
      expect(saved, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$surface preserves a confirmed save when its readback fails',
        (tester) async {
      var fail = false;
      var saved = false;
      final writes = <http.Request>[];
      respond = (r) async {
        if (r.url.path.endsWith('/saved_posts')) {
          if (r.method == 'GET') {
            return fail
                ? json(r, {'code': 'XX000', 'message': 'Read failed'}, 400)
                : json(r, [
                    if (saved) {'post_id': 'fixture-post'}
                  ]);
          }
          writes.add(r);
          saved = r.method == 'POST';
          fail = writes.length == 1;
          return http.Response('', 204, request: r);
        }
        return savedOtherResponse(r);
      };
      await renderSavedSurface(tester, savedScope(), surface);
      await tester.tap(savedButton(surface, false));
      await saveFrames(tester);
      expect(saved, isTrue);
      expect(savedButton(surface, true), findsOneWidget);
      expect(
          find.text('Өөрчлөлт хадгалагдсан. Жагсаалтыг дахин татаж чадсангүй.'),
          findsOneWidget);
      fail = false;
      await tester.tap(savedButton(surface, true));
      await saveFrames(tester);
      expect(writes.map((r) => r.method), ['POST', 'DELETE']);
      expect(saved, isFalse);
      expect(savedButton(surface, false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$surface cannot finish a saved-state action in another account',
        (tester) async {
      final pending = Completer<http.Response>();
      http.Request? heldRequest;
      final writes = <http.Request>[];
      respond = (r) async {
        if (r.url.path.endsWith('/saved_posts')) {
          if (r.method == 'GET') {
            if (r.url.queryParameters['user_id'] == 'eq.$me') {
              heldRequest = r;
              return pending.future;
            }
            return json(r, []);
          }
          writes.add(r);
          return http.Response('', 204, request: r);
        }
        return savedOtherResponse(r);
      };
      final account = StateProvider<String?>((ref) => me);
      final container = savedScope(account: account);
      await renderSavedSurface(tester, container, surface);
      await tester.tap(savedButton(surface, false));
      await tester.pump();
      container.read(account.notifier).state = other;
      await tester.pump();
      pending.complete(json(heldRequest!, [
        {'post_id': 'fixture-post'}
      ]));
      await saveFrames(tester);
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('private follow and DM actions use guarded RPCs and preserve denial',
      () async {
    respond = (r) async => json(
        r, r.url.path.endsWith('set_follow') ? 'requested' : 'fixture-message');
    expect(await service.follow(other, true), 'requested');
    await service.send(other, 'Hello',
        story: 'story-id', venue: 'osm:node:123');
    expect(requests.map((r) => r.url.path),
        ['/rest/v1/rpc/set_follow', '/rest/v1/rpc/send_direct_message']);
    expect(jsonDecode(requests.last.body)['p_story'], 'story-id');
    respond =
        (r) async => json(r, {'code': '42501', 'message': 'Blocked'}, 403);
    await expectLater(
        service.send(other, 'Again'), throwsA(isA<PostgrestException>()));
    expect(const SocialRelationship().canSend, isFalse);
    for (final state in ['requested', 'incoming', 'closed', 'blocked']) {
      expect(SocialRelationship(dmState: state).canSend, isFalse);
    }
  });

  test('Following uses a separate server query and a composite cursor',
      () async {
    respond = (r) async {
      expect(r.url.path, '/rest/v1/rpc/get_discovery_feed');
      final params = jsonDecode(r.body) as Map;
      expect(params['p_following'], isTrue);
      return json(
          r,
          params['p_before'] == null
              ? List.generate(
                  20,
                  (i) => {
                        'id':
                            '30000000-0000-0000-0000-${(20 - i).toString().padLeft(12, '0')}',
                        'user_id': other,
                        'created_at': '2026-10-16T00:00:00Z',
                        'caption': 'Followed creator',
                      })
              : []);
    };
    final feed = FeedNotifier(followingOnly: true);
    addTearDown(feed.dispose);
    while (feed.state.isLoading) {
      await Future<void>.delayed(Duration.zero);
    }
    await feed.loadFeed();
    final params = jsonDecode(requests.last.body) as Map;
    expect(params['p_before_id'], '30000000-0000-0000-0000-000000000001');
    expect(params['p_before'], isNotNull);
    expect(feed.state.value, hasLength(20));
    expect(feed.hasMore.value, isFalse);
  });

  test('source venue links survive post parsing and optimistic copies', () {
    final post = Post.fromJson({
      'id': 'post',
      'user_id': me,
      'venue_ref': 'osm:node:123',
      'venue_name': 'Source place',
      'created_at': '2026-10-16T00:00:00Z'
    });
    expect(post.venueId, isNull);
    expect(post.copyWith(isLikedByMe: true).venueRef, 'osm:node:123');
  });

  testWidgets('detail reactions update both feeds and ignore duplicate taps',
      (tester) async {
    final post = Post(
        id: 'fixture-post',
        userId: other,
        createdAt: DateTime.utc(2026, 10, 16),
        likesCount: 4);
    final all = _FixtureFeed(post);
    final following = _FixtureFeed(post);
    final held = Completer<http.Response>();
    http.Request? likeRequest;
    respond = (r) async {
      if (r.url.path.endsWith('/posts')) {
        return json(r, {
          'id': post.id,
          'user_id': other,
          'created_at': post.createdAt.toIso8601String(),
          'likes_count': 4,
          'caption': 'Fixture post',
        });
      }
      if (r.url.path.endsWith('/profiles')) {
        return json(r, {'id': me, 'username': 'fixture_me'});
      }
      if (r.url.path.endsWith('/likes')) {
        if (r.method == 'POST') {
          likeRequest = r;
          return held.future;
        }
        if (r.method == 'DELETE') {
          return json(r, {'code': '42501', 'message': 'Fixture denial'}, 403);
        }
        return http.Response('null', 200,
            request: r, headers: {'content-type': 'application/json'});
      }
      return json(r, []);
    };
    final container = ProviderContainer(overrides: [
      feedProvider.overrideWith((ref) => all),
      followingFeedProvider.overrideWith((ref) => following),
      commentsProvider(post.id).overrideWith((ref) => Stream.value([])),
    ]);
    addTearDown(container.dispose);
    container.read(followingFeedProvider);
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PostDetailScreen(postId: post.id))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.favorite_border));
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    expect(
        requests
            .where((r) => r.url.path.endsWith('/likes') && r.method == 'POST'),
        hasLength(1));
    expect(
        requests.where(
            (r) => r.url.path.endsWith('/likes') && r.method == 'DELETE'),
        isEmpty);
    held.complete(http.Response('', 204, request: likeRequest));
    await tester.pumpAndSettle();
    for (final feed in [all, following]) {
      expect(feed.state.value!.single.isLikedByMe, isTrue,
          reason:
              '${identical(feed, all) ? 'all' : 'following'}: ${requests.map((r) => '${r.method} ${r.url.path}').toList()}');
      expect(feed.state.value!.single.likesCount, 5);
    }
    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();
    for (final feed in [all, following]) {
      expect(feed.state.value!.single.isLikedByMe, isTrue);
      expect(feed.state.value!.single.likesCount, 5);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final currentlyLiked in [false, true]) {
    for (final denied in [false, true]) {
      test(
          'detail reaction honors caller state with stale feed, liked=$currentlyLiked denied=$denied',
          () async {
        final cached = Post(
            id: 'reaction-post',
            userId: other,
            createdAt: DateTime.utc(2026, 10, 16),
            isLikedByMe: !currentlyLiked,
            likesCount: 3);
        final feed = _FixtureFeed(cached);
        addTearDown(feed.dispose);
        respond = (r) async => denied
            ? json(r, {'code': '42501', 'message': 'Fixture denial'}, 403)
            : http.Response('', 204, request: r);
        final ok = await feed.toggleLikeById(cached.id, currentlyLiked);
        final writes =
            requests.where((r) => r.url.path.endsWith('/likes')).toList();
        expect(writes, hasLength(1));
        expect(writes.single.method, currentlyLiked ? 'DELETE' : 'POST');
        if (currentlyLiked) {
          expect(
              writes.single.url.queryParameters['post_id'], 'eq.${cached.id}');
          expect(writes.single.url.queryParameters['user_id'], 'eq.$me');
        } else {
          expect(jsonDecode(writes.single.body),
              {'user_id': me, 'post_id': cached.id});
        }
        expect(ok, !denied);
        expect(feed.state.value!.single.isLikedByMe, !currentlyLiked);
        expect(feed.state.value!.single.likesCount, 3,
            reason:
                'The cache already has the desired reaction; do not count it twice.');
      });
    }
  }

  for (final cached in [false, true]) {
    test('detail reaction serializes duplicate writes, post cached=$cached',
        () async {
      final post = Post(
          id: cached ? 'reaction-post' : 'other-post',
          userId: other,
          createdAt: DateTime.utc(2026, 10, 16));
      final feed = _FixtureFeed(post);
      addTearDown(feed.dispose);
      final response = Completer<http.Response>();
      http.Request? heldRequest;
      respond = (r) {
        heldRequest = r;
        return response.future;
      };
      final pending = feed.toggleLikeById('reaction-post', false);
      final duplicate = feed.toggleLikeById('reaction-post', true);
      // Drain request scheduling without leaving the first write unresolved.
      await Future<void>.delayed(Duration.zero);
      final writes =
          requests.where((r) => r.url.path.endsWith('/likes')).toList();
      response.complete(http.Response('', 204, request: heldRequest));
      expect(await pending, isTrue);
      expect(await duplicate, isFalse);
      expect(writes, hasLength(1));
      expect(writes.single.method, 'POST');
    });
  }

  test('reaction denial releases the guard for a later retry outside the feed',
      () async {
    final feed = _FixtureFeed(Post(
        id: 'other-post',
        userId: other,
        createdAt: DateTime.utc(2026, 10, 16)));
    addTearDown(feed.dispose);
    var denied = true;
    respond = (r) async => denied
        ? json(r, {'code': '42501', 'message': 'Fixture denial'}, 403)
        : http.Response('', 204, request: r);
    expect(await feed.toggleLikeById('reaction-post', false), isFalse);
    denied = false;
    expect(await feed.toggleLikeById('reaction-post', false), isTrue);
    expect(requests.where((r) => r.url.path.endsWith('/likes')), hasLength(2));
    expect(feed.state.value!.single.id, 'other-post');
  });

  test('removing an inconsistent zero-count reaction never makes it negative',
      () async {
    final feed = _FixtureFeed(Post(
        id: 'reaction-post',
        userId: other,
        createdAt: DateTime.utc(2026, 10, 16),
        isLikedByMe: true));
    addTearDown(feed.dispose);
    respond = (r) async => http.Response('', 204, request: r);
    expect(await feed.toggleLike('reaction-post'), isTrue);
    expect(requests.single.method, 'DELETE');
    expect(feed.state.value!.single.isLikedByMe, isFalse);
    expect(feed.state.value!.single.likesCount, 0);
  });

  test('a disposed account feed cannot start a new off-feed reaction write',
      () async {
    final feed = _FixtureFeed(Post(
        id: 'other-post',
        userId: other,
        createdAt: DateTime.utc(2026, 10, 16)));
    feed.dispose();
    respond = (r) async => http.Response('', 204, request: r);
    expect(await feed.toggleLikeById('reaction-post', false), isFalse);
    expect(requests, isEmpty);
  });

  test(
      'reaction rollback preserves a caption saved while the write was pending',
      () async {
    final feed = _FixtureFeed(Post(
        id: 'reaction-post',
        userId: me,
        caption: 'Old caption',
        createdAt: DateTime.utc(2026, 10, 16)));
    addTearDown(feed.dispose);
    final pending = Completer<http.Response>();
    http.Request? heldRequest;
    respond = (r) async {
      if (r.url.path.endsWith('/likes')) {
        heldRequest = r;
        return pending.future;
      }
      return json(r, {'id': 'reaction-post'});
    };
    final reaction = feed.toggleLike('reaction-post');
    await Future<void>.delayed(Duration.zero);
    await feed.editCaption('reaction-post', 'New caption');
    pending.complete(
        json(heldRequest!, {'code': '42501', 'message': 'Denied'}, 403));
    expect(await reaction, isFalse);
    expect(feed.state.value!.single.caption, 'New caption');
    expect(feed.state.value!.single.isLikedByMe, isFalse);
    expect(feed.state.value!.single.likesCount, 0);
  });

  for (final denied in [false, true]) {
    testWidgets('detail zero-count unlike stays nonnegative, denied=$denied',
        (tester) async {
      final feed = _FixtureFeed(Post(
          id: 'reaction-post',
          userId: other,
          createdAt: DateTime.utc(2026, 10, 16),
          isLikedByMe: true));
      respond = (r) async {
        if (r.url.path.endsWith('/posts')) {
          return json(r, {
            'id': 'reaction-post',
            'user_id': other,
            'created_at': '2026-10-16T00:00:00Z',
            'likes_count': 0
          });
        }
        if (r.url.path.endsWith('/profiles')) {
          return json(r, {'id': me, 'username': 'fixture_me'});
        }
        if (r.url.path.endsWith('/likes')) {
          if (r.method == 'GET') return json(r, {'post_id': 'reaction-post'});
          return denied
              ? json(r, {'code': '42501', 'message': 'Denied'}, 403)
              : http.Response('', 204, request: r);
        }
        return json(r, []);
      };
      final container = ProviderContainer(overrides: [
        sessionUserIdProvider.overrideWithValue(me),
        feedProvider.overrideWith((ref) => feed),
        commentsProvider('reaction-post')
            .overrideWith((ref) => Stream.value([])),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
              home: PostDetailScreen(postId: 'reaction-post'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      expect(find.byIcon(denied ? Icons.favorite : Icons.favorite_border),
          findsOneWidget);
      expect(find.text('-1'), findsNothing);
      expect(feed.state.value!.single.likesCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final trigger in ['account', 'privacy']) {
    testWidgets(
        'post details discard cached post, comments and draft on $trigger change',
        (tester) async {
      final pending = Completer<http.Response>();
      http.Request? heldRequest;
      var loads = 0;
      respond = (r) async {
        if (r.url.path.endsWith('/posts')) {
          if (++loads > 1) {
            heldRequest = r;
            return pending.future;
          }
          return json(r, {
            'id': 'private-post',
            'user_id': other,
            'caption': 'Cached private post',
            'created_at': '2026-10-16T00:00:00Z'
          });
        }
        if (r.url.path.endsWith('/profiles')) {
          return json(r, {'id': me, 'username': 'fixture_me'});
        }
        if (r.url.path.endsWith('/likes')) {
          return http.Response('null', 200,
              headers: {'content-type': 'application/json'}, request: r);
        }
        return json(r, []);
      };
      final account = StateProvider<String?>((ref) => me);
      final container = ProviderContainer(overrides: [
        sessionUserIdProvider.overrideWith((ref) => ref.watch(account)),
        commentsProvider('private-post').overrideWith((ref) => Stream.value([
              Comment(
                  id: 'private-comment',
                  postId: 'private-post',
                  userId: other,
                  body: 'Cached private comment',
                  createdAt: DateTime.utc(2026, 10, 16))
            ])),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
              home: PostDetailScreen(postId: 'private-post'))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cached private post', findRichText: true),
          findsOneWidget);
      expect(find.text('Cached private comment'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Private draft');
      if (trigger == 'account') {
        container.read(account.notifier).state = other;
      } else {
        container.read(socialVersionProvider.notifier).state++;
      }
      await tester.pump();
      final showedOldPost = find
          .textContaining('Cached private post', findRichText: true)
          .evaluate()
          .isNotEmpty;
      final showedOldComment =
          find.text('Cached private comment').evaluate().isNotEmpty;
      final showedOldDraft = find.text('Private draft').evaluate().isNotEmpty;
      pending.complete(http.Response('null', 200,
          headers: {'content-type': 'application/json'}, request: heldRequest));
      await tester.pumpAndSettle();
      expect(heldRequest, isNotNull);
      expect(showedOldPost, isFalse);
      expect(showedOldComment, isFalse);
      expect(showedOldDraft, isFalse);
      expect(find.text('Пост олдсонгүй'), findsOneWidget);
      expect(find.text('Cached private comment'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('an old detail response cannot replace a newer shared post route',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? heldRequest;
    respond = (r) async {
      if (r.url.path.endsWith('/posts')) {
        if (r.url.queryParameters['id'] == 'eq.first-post') {
          heldRequest = r;
          return pending.future;
        }
        return json(r, {
          'id': 'second-post',
          'user_id': other,
          'caption': 'Second post',
          'created_at': '2026-10-16T00:00:00Z'
        });
      }
      if (r.url.path.endsWith('/profiles')) {
        return json(r, {'id': me, 'username': 'fixture_me'});
      }
      if (r.url.path.endsWith('/likes')) {
        return http.Response('null', 200,
            headers: {'content-type': 'application/json'}, request: r);
      }
      return json(r, []);
    };
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWithValue(me),
      for (final id in ['first-post', 'second-post'])
        commentsProvider(id).overrideWith((ref) => Stream.value([])),
    ]);
    addTearDown(container.dispose);
    Future<void> render(String id) =>
        tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: PostDetailScreen(postId: id))));
    await render('first-post');
    await tester.pump(const Duration(milliseconds: 100));
    await render('second-post');
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    pending.complete(json(heldRequest!, {
      'id': 'first-post',
      'user_id': other,
      'caption': 'Late first post',
      'created_at': '2026-10-16T00:00:00Z'
    }));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Second post', findRichText: true), findsOneWidget);
    expect(find.textContaining('Late first post', findRichText: true),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final action in ['like', 'comment']) {
    testWidgets('late $action result cannot change a new post or its draft',
        (tester) async {
      final pending = Completer<http.Response>();
      http.Request? heldRequest;
      respond = (r) async {
        if (r.url.path.endsWith('/posts')) {
          final id = r.url.queryParameters['id']!.substring(3);
          return json(r, {
            'id': id,
            'user_id': other,
            'caption': 'Caption $id',
            'created_at': '2026-10-16T00:00:00Z',
            'likes_count': 3
          });
        }
        if (r.url.path.endsWith('/profiles')) {
          return json(r, {'id': me, 'username': 'fixture_me'});
        }
        if (r.method == 'POST' &&
            r.url.path.endsWith(action == 'like' ? '/likes' : '/comments')) {
          heldRequest = r;
          return pending.future;
        }
        if (r.url.path.endsWith('/likes')) {
          return http.Response('null', 200,
              headers: {'content-type': 'application/json'}, request: r);
        }
        return json(r, []);
      };
      final seed = _FixtureFeed(Post(
          id: 'first-post',
          userId: other,
          createdAt: DateTime.utc(2026, 10, 16),
          likesCount: 3));
      final container = ProviderContainer(overrides: [
        sessionUserIdProvider.overrideWithValue(me),
        feedProvider.overrideWith((ref) => seed),
        for (final id in ['first-post', 'second-post'])
          commentsProvider(id).overrideWith((ref) => Stream.value([])),
      ]);
      addTearDown(container.dispose);
      Future<void> render(String id) =>
          tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: MaterialApp(home: PostDetailScreen(postId: id))));
      await render('first-post');
      await tester.pumpAndSettle();
      if (action == 'like') {
        await tester.tap(find.byIcon(Icons.favorite_border));
      } else {
        await tester.enterText(find.byType(TextField), 'First post draft');
        await tester.tap(find.byIcon(Icons.send_rounded));
      }
      await tester.pump();
      expect(heldRequest, isNotNull);
      await render('second-post');
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.enterText(find.byType(TextField), 'Second post draft');
      pending.complete(action == 'like'
          ? json(
              heldRequest!, {'code': '42501', 'message': 'Fixture denial'}, 403)
          : http.Response('', 204, request: heldRequest));
      await tester.pumpAndSettle();
      expect(find.textContaining('Caption second-post', findRichText: true),
          findsOneWidget);
      expect(find.text('Second post draft'), findsOneWidget);
      expect(find.text('Лайк илгээж чадсангүй'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final surface in ['feed', 'detail']) {
    for (final initiallySaved in [false, true]) {
      for (final denied in [false, true]) {
        testWidgets(
            '$surface save guards duplicate taps, saved=$initiallySaved denied=$denied',
            (tester) async {
          const id = 'fixture-post';
          final pending = Completer<http.Response>();
          final writes = <http.Request>[];
          final remote = <String>{if (initiallySaved) id};
          respond = (r) async {
            if (r.url.path.endsWith('/saved_posts')) {
              if (r.method == 'GET') {
                return json(r, [
                  for (final saved in remote) {'post_id': saved}
                ]);
              }
              writes.add(r);
              final response = await pending.future;
              if (!denied) {
                if (r.method == 'POST') remote.add(id);
                if (r.method == 'DELETE') remote.remove(id);
              }
              return response;
            }
            if (r.url.path.endsWith('/posts')) {
              return json(r, {
                'id': id,
                'user_id': other,
                'caption': 'Fixture post',
                'created_at': '2026-10-16T00:00:00Z'
              });
            }
            if (r.url.path.endsWith('/profiles')) {
              return json(r, {'id': me, 'username': 'fixture_me'});
            }
            if (r.url.path.endsWith('/likes')) {
              return http.Response('null', 200,
                  headers: {'content-type': 'application/json'}, request: r);
            }
            return json(r, []);
          };
          final feed = _FixtureFeed(Post(
              id: id,
              userId: other,
              createdAt: DateTime.utc(2026, 10, 16),
              caption: 'Fixture post'));
          final container = ProviderContainer(overrides: [
            sessionUserIdProvider.overrideWithValue(me),
            currentProfileProvider.overrideWith((ref) async => null),
            feedProvider.overrideWith((ref) => feed),
            commentsProvider(id).overrideWith((ref) => Stream.value([])),
            storiesProvider.overrideWith((ref) async => []),
            feedFollowingIdsProvider.overrideWith((ref) async => {}),
            upcomingEventsProvider.overrideWith((ref) async => []),
            unreadNotifCountProvider.overrideWithValue(0),
          ]);
          addTearDown(container.dispose);
          tester.view.physicalSize = const Size(390, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                  home: surface == 'feed'
                      ? const FeedScreen()
                      : const PostDetailScreen(postId: id))));
          await tester.pumpAndSettle();
          Finder button(bool saved) => surface == 'feed'
              ? find.byTooltip(saved ? 'Хадгалснаас хасах' : 'Хадгалах')
              : find.byIcon(saved ? Icons.bookmark : Icons.bookmark_border);
          await tester.ensureVisible(button(initiallySaved));
          await tester.tap(button(initiallySaved));
          await tester.pump();
          await tester.tap(button(!initiallySaved));
          await tester.pump();
          final writeCount = writes.length;
          pending.complete(denied
              ? json(writes.first, {'code': '42501', 'message': 'Denied'}, 403)
              : http.Response('', 204, request: writes.first));
          await tester.pumpAndSettle();
          expect(writeCount, 1);
          expect(writes.single.method, initiallySaved ? 'DELETE' : 'POST');
          if (initiallySaved) {
            expect(writes.single.url.queryParameters['post_id'], 'eq.$id');
            expect(writes.single.url.queryParameters['user_id'], 'eq.$me');
          } else {
            expect(
                jsonDecode(writes.single.body), {'user_id': me, 'post_id': id});
          }
          final saved = denied ? initiallySaved : !initiallySaved;
          expect(remote.contains(id), saved);
          expect(button(saved), findsOneWidget);
          if (denied) {
            expect(
                find.text(initiallySaved
                    ? 'Хадгалснаа хасаж чадсангүй'
                    : 'Хадгалж чадсангүй. Дахин оролдоно уу'),
                findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  for (final trigger in ['account', 'signout', 'privacy']) {
    testWidgets('saved posts discard the previous list on $trigger change',
        (tester) async {
      final pending = Completer<http.Response>();
      http.Request? heldRequest;
      var loads = 0;
      respond = (r) async {
        if (r.url.path.endsWith('/saved_posts')) {
          if (++loads > 1) {
            heldRequest = r;
            return pending.future;
          }
          return json(r, [
            {'post_id': 'private-post'}
          ]);
        }
        return json(r, [
          {'id': 'private-post', 'media_url': null}
        ]);
      };
      final account = StateProvider<String?>((ref) => me);
      final container = ProviderContainer(overrides: [
        sessionUserIdProvider.overrideWith((ref) => ref.watch(account)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SavedPostsScreen())));
      await tester.pumpAndSettle();
      expect(find.text('1 пост'), findsOneWidget);
      if (trigger == 'privacy') {
        container.read(socialVersionProvider.notifier).state++;
      } else {
        container.read(account.notifier).state =
            trigger == 'signout' ? null : other;
      }
      await tester.pump();
      final showedOldList = find.text('1 пост').evaluate().isNotEmpty;
      pending.complete(http.Response('[]', 200,
          headers: {'content-type': 'application/json'}, request: heldRequest));
      await tester.pumpAndSettle();
      expect(showedOldList, isFalse);
      expect(find.text('Хадгалсан пост алга'), findsOneWidget);
      if (trigger != 'signout') expect(heldRequest, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('late saved-post media cannot restore a previous account list',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? heldRequest;
    var reads = 0;
    respond = (r) async {
      if (r.url.path.endsWith('/saved_posts')) {
        return json(
            r,
            ++reads == 1
                ? [
                    {'post_id': 'private-post'}
                  ]
                : []);
      }
      heldRequest = r;
      return pending.future;
    };
    final account = StateProvider<String?>((ref) => me);
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(account)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SavedPostsScreen())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(heldRequest, isNotNull);
    container.read(account.notifier).state = other;
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    pending.complete(json(heldRequest!, [
      {'id': 'private-post', 'media_url': null}
    ]));
    await tester.pumpAndSettle();
    expect(find.text('1 пост'), findsNothing);
    expect(find.text('Хадгалсан пост алга'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saved posts refresh failure offers a working retry',
      (tester) async {
    var fail = false;
    respond = (r) async {
      if (r.url.path.endsWith('/saved_posts')) {
        return fail
            ? json(r, {'code': 'XX000', 'message': 'Read failed'}, 400)
            : json(r, [
                {'post_id': 'fixture-post'}
              ]);
      }
      return json(r, [
        {'id': 'fixture-post', 'media_url': null}
      ]);
    };
    await tester.pumpWidget(ProviderScope(
        overrides: [sessionUserIdProvider.overrideWithValue(me)],
        child: const MaterialApp(home: SavedPostsScreen())));
    await tester.pumpAndSettle();
    fail = true;
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Хадгалсан постуудыг ачаалж чадсангүй'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('1 пост'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DM approvals refresh while visible and fail closed offline',
      (tester) async {
    var state = 'requested';
    var offline = false;
    var checks = 0;
    respond = (r) async {
      if (r.url.path.endsWith('/profiles')) {
        return json(r, {'id': other, 'username': 'fixture_creator'});
      }
      if (r.url.path.endsWith('/get_relationship')) {
        checks++;
        if (offline) return json(r, {'message': 'Fixture offline'}, 503);
        return json(r, {'dm_state': state, 'can_view': true, 'blocked': false});
      }
      return json(r, []);
    };
    final router = GoRouter(routes: [
      GoRoute(
          path: '/', builder: (_, __) => const DmThreadScreen(threadId: other)),
      GoRoute(
          path: '/covered',
          builder: (_, __) => const Scaffold(body: Text('Covered'))),
    ]);
    addTearDown(router.dispose);
    final send = find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.label == 'Мессеж илгээх');
    bool canSend() => tester.widget<Semantics>(send).properties.enabled == true;
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'Unsent fixture draft');
    await tester.pumpAndSettle();
    expect(canSend(), isFalse);
    expect(
        requests.where(
            (r) => r.method == 'PATCH' && r.url.path.endsWith('/messages')),
        isEmpty);
    state = 'accepted';
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(canSend(), isTrue);
    expect(
        requests.any(
            (r) => r.method == 'PATCH' && r.url.path.endsWith('/messages')),
        isTrue);
    offline = true;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(canSend(), isFalse);
    expect(find.text('Мессежийн эрхийг шалгаж чадсангүй'), findsOneWidget);
    router.push('/covered');
    await tester.pumpAndSettle();
    final hiddenChecks = checks;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(checks, hiddenChecks);
    router.pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 30));
    expect(checks, hiddenChecks);
    offline = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(canSend(), isTrue);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'Unsent fixture draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('an older permission check cannot undo a new DM approval',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? heldRequest;
    var checks = 0;
    var approvals = 0;
    var state = 'incoming';
    respond = (r) async {
      if (r.url.path.endsWith('/profiles')) {
        return json(r, {'id': other, 'username': 'fixture_creator'});
      }
      if (r.url.path.endsWith('/respond_message_request')) {
        approvals++;
        state = 'accepted';
        return http.Response('', 204, request: r);
      }
      if (r.url.path.endsWith('/get_relationship')) {
        checks++;
        if (checks == 2) {
          heldRequest = r;
          return held.future;
        }
        return json(r, {'dm_state': state, 'can_view': true});
      }
      return json(r, []);
    };
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/', builder: (_, __) => const DmThreadScreen(threadId: other)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Fixture draft');
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(checks, 2);
    await tester.tap(find.byTooltip('Зөвшөөрөх'));
    await tester.pump();
    expect(approvals, 1);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check))
            .onPressed,
        isNull);
    held.complete(
        json(heldRequest!, {'dm_state': 'incoming', 'can_view': true}));
    await tester.pumpAndSettle();
    expect(checks, 3);
    expect(find.text('Мессежийн хүсэлт'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('saved places import local entries once then honor server removals',
      () async {
    SharedPreferences.setMockInitialValues({
      'venue_bookmarks.$me': ['osm:node:123']
    });
    final remote = <String>{};
    respond = (r) async {
      if (r.method == 'POST') {
        expect(r.url.path, '/rest/v1/rpc/import_venue_saves');
        final params = jsonDecode(r.body) as Map;
        expect(params['p_owner'], me);
        remote.addAll((params['p_refs'] as List).cast<String>());
        return json(r, remote.length);
      }
      return json(r, remote.map((id) => {'venue_ref': id}).toList());
    };
    final first = VenueBookmarksNotifier(me, backend: service);
    await first.ready;
    expect(first.state.valueOrNull, {'osm:node:123'});
    expect(remote, {'osm:node:123'});
    first.dispose();
    remote.clear();
    final next = VenueBookmarksNotifier(me, backend: service);
    addTearDown(next.dispose);
    await next.ready;
    expect(next.state.valueOrNull, isEmpty);
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test('bookmark import stops if the account changes before it completes',
      () async {
    SharedPreferences.setMockInitialValues({
      'venue_bookmarks.$me': ['osm:node:123', 'obsolete-place'],
    });
    respond = (r) async {
      if (r.url.path.endsWith('/import_venue_saves')) {
        expect((jsonDecode(r.body) as Map)['p_owner'], me);
        await Supabase.instance.client.auth.signOut();
        return json(r, 1);
      }
      return json(r, []);
    };
    final notifier = VenueBookmarksNotifier(me, backend: service);
    addTearDown(notifier.dispose);
    await notifier.ready;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('venue_bookmarks.$me.synced'), isNull);
    expect(
        requests.where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/venue_saves')),
        isEmpty);
  });

  test('signed-in saves follow server success and preserve state on denial',
      () async {
    SharedPreferences.setMockInitialValues(
        {'venue_bookmarks.$me.synced': true});
    final remote = <String>{};
    var denied = false;
    respond = (r) async {
      if (r.method == 'GET') {
        return json(r, remote.map((id) => {'venue_ref': id}).toList());
      }
      if (denied) {
        return json(r, {'code': '42501', 'message': 'Fixture denial'}, 403);
      }
      if (r.method == 'POST') {
        final body = jsonDecode(r.body) as Map;
        expect(body['user_id'], me);
        remote.add(body['venue_ref'] as String);
      } else if (r.method == 'DELETE') {
        remote.remove(r.url.queryParameters['venue_ref']!.substring(3));
      }
      return http.Response('', 204, request: r);
    };
    final notifier = VenueBookmarksNotifier(me, backend: service);
    addTearDown(notifier.dispose);
    await notifier.ready;
    await notifier.toggle('osm:node:123');
    expect(remote, {'osm:node:123'});
    expect(notifier.state.value, remote);
    denied = true;
    await expectLater(
        notifier.toggle('osm:node:123'), throwsA(isA<PostgrestException>()));
    expect(notifier.state.value, {'osm:node:123'});
    denied = false;
    await notifier.toggle('osm:node:123');
    expect(notifier.state.value, isEmpty);
    expect(remote, isEmpty);
  });

  test('media signing only applies to our protected storage origin', () {
    expect(
        protectedStorageObject(
            'https://example.test/storage/v1/object/public/posts/$me/a.jpg',
            backend: 'https://example.test'),
        (bucket: 'posts', path: '$me/a.jpg'));
    expect(
        protectedStorageObject(
            'https://evil.test/storage/v1/object/public/posts/$me/a.jpg',
            backend: 'https://example.test'),
        isNull);
    expect(
        protectedStorageObject(
            'https://example.test/storage/v1/object/public/avatars/$me/a.jpg',
            backend: 'https://example.test'),
        isNull);
    expect(
        protectedStorageObject('blob:https://example.test/local',
            backend: 'https://example.test'),
        isNull);
  });

  testWidgets('place saves share the map cache and denied changes preserve it',
      (tester) async {
    const venueRef = 'osm:node:123';
    var remote = <String>{};
    var deny = false;
    respond = (r) async {
      if (r.url.path.endsWith('/venue_catalog')) {
        return json(r, {'ref': venueRef, 'name': 'Шалгалтын газар'});
      }
      if (r.url.path.endsWith('/venue_saves')) {
        if (r.method == 'GET') {
          return json(r, [
            for (final id in remote) {'venue_ref': id}
          ]);
        }
        if (deny) return json(r, {'code': '42501', 'message': 'Denied'}, 403);
        if (r.method == 'POST') remote.add(venueRef);
        if (r.method == 'DELETE') remote.remove(venueRef);
        return http.Response('', 204, request: r);
      }
      return json(r, []);
    };
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWithValue(me),
    ]);
    addTearDown(container.dispose);
    // The map stays mounted while a place route is on top of it.
    final mapListener = container.listen(venueBookmarksProvider, (_, __) {});
    addTearDown(mapListener.close);
    await container.read(venueBookmarksProvider.notifier).ready;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlaceScreen(venueRef: venueRef))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хадгалах'));
    await tester.pumpAndSettle();
    expect(remote, {venueRef});
    expect(container.read(venueBookmarksProvider).value, {venueRef});
    expect(find.text('Хадгалсан'), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance())
            .getStringList('venue_bookmarks.$me'),
        [venueRef]);
    deny = true;
    await tester.tap(find.text('Хадгалсан'));
    await tester.pumpAndSettle();
    expect(remote, {venueRef});
    expect(container.read(venueBookmarksProvider).value, {venueRef});
    expect(find.text('Хадгалсан'), findsOneWidget);
    expect(
        find.text(discoveryError(
            const PostgrestException(message: 'Denied', code: '42501'))),
        findsOneWidget);
    deny = false;
    await container.read(venueBookmarksProvider.notifier).toggle(venueRef);
    await tester.pumpAndSettle();
    expect(remote, isEmpty);
    expect(find.text('Хадгалах'), findsOneWidget,
        reason: 'A map-side change must also update the mounted place page.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bookmark loading failure does not hide public place information',
      (tester) async {
    var offline = true;
    respond = (r) async {
      if (r.url.path.endsWith('/venue_catalog')) {
        return json(r, {'ref': 'osm:node:123', 'name': 'Шалгалтын газар'});
      }
      if (r.url.path.endsWith('/venue_saves') && offline) {
        return json(r, {'code': 'XX000', 'message': 'Read failed'}, 400);
      }
      return json(r, []);
    };
    await tester.pumpWidget(ProviderScope(
        overrides: [sessionUserIdProvider.overrideWithValue(me)],
        child: const MaterialApp(home: PlaceScreen(venueRef: 'osm:node:123'))));
    await tester.pumpAndSettle();
    expect(find.text('Шалгалтын газар'), findsOneWidget);
    expect(find.text('Чиглэл авах'), findsOneWidget);
    expect(find.text('Хадгалалтыг дахин шалгах'), findsOneWidget);
    offline = false;
    await tester.tap(find.text('Хадгалалтыг дахин шалгах'));
    await tester.pumpAndSettle();
    expect(find.text('Хадгалах'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching accounts removes old place posts before reloading',
      (tester) async {
    final pendingPosts = Completer<http.Response>();
    http.Request? heldRequest;
    var loads = 0;
    respond = (r) async {
      if (r.url.path.endsWith('/venue_catalog')) {
        return json(r, {'ref': 'osm:node:123', 'name': 'Шалгалтын газар'});
      }
      if (r.url.path.endsWith('/posts')) {
        if (++loads > 1) {
          heldRequest = r;
          return pendingPosts.future;
        }
        return json(r, [
          {'id': 'private-post', 'caption': 'Previous account content'}
        ]);
      }
      return json(r, []);
    };
    final account = StateProvider<String?>((ref) => me);
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(account)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PlaceScreen(venueRef: 'osm:node:123'))));
    await tester.pumpAndSettle();
    expect(find.text('Previous account content'), findsOneWidget);
    container.read(account.notifier).state = other;
    await tester.pump();
    expect(find.text('Previous account content'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pendingPosts.complete(json(heldRequest!, []));
    await tester.pumpAndSettle();
    expect(find.text('Previous account content'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('place refresh contains failures and offers a working retry',
      (tester) async {
    var fail = false;
    respond = (r) async {
      if (r.url.path.endsWith('/venue_catalog')) {
        if (fail) {
          return json(r, {'code': 'XX000', 'message': 'Read failed'}, 400);
        }
        return json(r, {'ref': 'osm:node:123', 'name': 'Шалгалтын газар'});
      }
      return json(r, []);
    };
    await tester.pumpWidget(ProviderScope(
        overrides: [sessionUserIdProvider.overrideWithValue(me)],
        child: const MaterialApp(home: PlaceScreen(venueRef: 'osm:node:123'))));
    await tester.pumpAndSettle();
    fail = true;
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    await expectLater(refresh.onRefresh(), completes);
    await tester.pumpAndSettle();
    expect(find.text('Холбогдож чадсангүй. Дахин оролдоорой.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    fail = false;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('Шалгалтын газар'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final screen in ['place', 'collections']) {
    testWidgets('$screen removes cached private content after a social change',
        (tester) async {
      final pending = Completer<http.Response>();
      http.Request? heldRequest;
      var loads = 0;
      respond = (r) async {
        if (r.url.path.endsWith('/venue_catalog')) {
          return json(r, {'ref': 'osm:node:123', 'name': 'Шалгалтын газар'});
        }
        if (r.url.path
            .endsWith(screen == 'place' ? '/posts' : '/place_collections')) {
          if (++loads > 1) {
            heldRequest = r;
            return pending.future;
          }
          return json(r, [
            screen == 'place'
                ? {'id': 'private-post', 'caption': 'Cached private content'}
                : {
                    'id': 'private-list',
                    'title': 'Cached private content',
                    'is_public': false,
                    'collection_places': []
                  }
          ]);
        }
        return json(r, []);
      };
      final container = ProviderContainer(overrides: [
        sessionUserIdProvider.overrideWithValue(me),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: screen == 'place'
                  ? const PlaceScreen(venueRef: 'osm:node:123')
                  : const CollectionsScreen(userId: me))));
      await tester.pumpAndSettle();
      expect(find.text('Cached private content'), findsOneWidget);
      container.read(socialVersionProvider.notifier).state++;
      await tester.pump();
      expect(find.text('Cached private content'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(heldRequest, isNotNull);
      pending.complete(json(heldRequest!, []));
      await tester.pumpAndSettle();
      expect(find.text('Cached private content'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'collections discard private rows immediately when accounts change',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? heldRequest;
    var loads = 0;
    respond = (r) async {
      if (r.url.path.endsWith('/place_collections')) {
        if (++loads > 1) {
          heldRequest = r;
          return pending.future;
        }
        return json(r, [
          {
            'id': 'private-list',
            'title': 'First account private list',
            'is_public': false,
            'collection_places': []
          }
        ]);
      }
      return json(r, []);
    };
    final account = StateProvider<String?>((ref) => me);
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(account)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CollectionsScreen(userId: me))));
    await tester.pumpAndSettle();
    expect(find.text('First account private list'), findsOneWidget);
    expect(find.byTooltip('Цуглуулга нэмэх'), findsOneWidget);
    container.read(account.notifier).state = other;
    await tester.pump();
    expect(find.text('First account private list'), findsNothing);
    expect(find.byTooltip('Цуглуулга нэмэх'), findsNothing);
    expect(heldRequest, isNotNull);
    pending.complete(json(heldRequest!, []));
    await tester.pumpAndSettle();
    expect(find.text('Цуглуулга алга'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('collections reload when a different profile uses the same route',
      (tester) async {
    final queried = <String?>[];
    respond = (r) async {
      if (r.url.path.endsWith('/place_collections')) {
        final owner = r.url.queryParameters['user_id'];
        queried.add(owner);
        return json(r, [
          {
            'id': 'list-$owner',
            'title': 'List for $owner',
            'is_public': true,
            'collection_places': []
          }
        ]);
      }
      return json(r, []);
    };
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWithValue(me),
    ]);
    addTearDown(container.dispose);
    Future<void> render(String owner) =>
        tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: CollectionsScreen(userId: owner))));
    await render(me);
    await tester.pumpAndSettle();
    expect(find.text('List for eq.$me'), findsOneWidget);
    await render(other);
    await tester.pumpAndSettle();
    expect(queried, ['eq.$me', 'eq.$other']);
    expect(find.text('List for eq.$me'), findsNothing);
    expect(find.text('List for eq.$other'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching accounts removes previously signed media immediately',
      (tester) async {
    final nextAccount = Completer<http.Response>();
    var signed = 0;
    respond = (r) async {
      if (r.url.path.contains('/object/sign/')) {
        signed++;
        if (signed == 1) {
          return json(r, {'signedURL': '/object/sign/posts/first?token=first'});
        }
        return nextAccount.future;
      }
      return json(r, []);
    };
    final account = StateProvider<String?>((ref) => me);
    final container = ProviderContainer(overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(account))
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: AuthorizedMedia(
                url:
                    '${AppConstants.backendUrl}/storage/v1/object/public/posts/$me/photo.jpg',
                placeholder: () => const Text('loading'),
                builder: (url) => Text(url.contains('token=first')
                    ? 'first account media'
                    : 'next account media')))));
    await tester.pumpAndSettle();
    expect(find.text('first account media'), findsOneWidget);
    container.read(account.notifier).state = other;
    await tester.pump();
    expect(find.text('first account media'), findsNothing);
    expect(find.text('loading'), findsOneWidget);
    nextAccount.complete(http.Response(
        jsonEncode({'signedURL': '/object/sign/posts/next?token=next'}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpAndSettle();
    expect(find.text('next account media'), findsOneWidget);
  });
  test(
      'auth return rejects external redirects and preserves a public shared list',
      () async {
    for (final url in [
      'https://evil.test',
      '//evil.test',
      '/\\evil.test',
      '/auth/login',
      '/post/create'
    ]) {
      expect(AuthReturn.valid(url), isNull);
    }
    AuthReturn.remember('/collections/$other?list=collection');
    await Future<void>.delayed(Duration.zero);
    await AuthReturn.restore();
    expect(AuthReturn.destination, '/collections/$other?list=collection');
    expect(cohortPercent(0, 0), 'Хугацаа болоогүй');
    expect(cohortPercent(1, 4), '25.0% (1/4)');
    AuthReturn.remember('/post/first');
    AuthReturn.clear();
    AuthReturn.remember('/place/osm%3Anode%3A123');
    await AuthReturn.restore();
    expect(AuthReturn.destination, '/place/osm%3Anode%3A123');
    AuthReturn.remember('/dm/$other');
    await AuthReturn.restore();
    expect(AuthReturn.destination, '/dm/$other');
    expect(AuthReturn.valid('/dm/not-a-user'), isNull);
  });

  testWidgets(
      'privacy controls and follow approvals work at 320px with large text',
      (tester) async {
    var private = false;
    respond = (r) async {
      if (r.url.path.endsWith('/profiles')) {
        if (r.method == 'PATCH') {
          private = (jsonDecode(r.body) as Map)['is_private'] == true;
          return json(r, {'id': me});
        }
        return json(r, {'is_private': private, 'dm_policy': 'requests'});
      }
      if (r.url.path.endsWith('/follow_requests')) {
        return json(r, [
          {
            'requester_id': other,
            'profiles': {'username': 'fixture_creator'}
          }
        ]);
      }
      return http.Response('', 204, request: r);
    };
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [sessionUserIdProvider.overrideWithValue(me)],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: const PrivacyScreen())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(private, isTrue);
    await tester.ensureVisible(find.byTooltip('Зөвшөөрөх'));
    await tester.tap(find.byTooltip('Зөвшөөрөх'));
    await tester.pumpAndSettle();
    expect(requests.any((r) => r.url.path.endsWith('respond_follow_request')),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    for (final screen in <String, Widget Function()>{
      'discovery': () => const DiscoveryScreen(),
      'collections': () => const CollectionsScreen(userId: me),
      'place': () => const PlaceScreen(venueRef: 'osm:node:123'),
      'review': () => const ReviewPlaceScreen(venueRef: 'osm:node:123'),
      'pilot': () => const PilotScreen(),
    }.entries) {
      testWidgets('${screen.key} fits $width pixels with large text',
          (tester) async {
        final venue = <String, dynamic>{
          'ref': 'osm:node:123',
          'name': 'Шалгалтын урт нэртэй газар',
          'address': 'Шалгалтын урт хаяг, Улаанбаатар',
          'hours': 'Даваа–Ням 10:00–23:00',
          'price_min': 10000,
          'price_max': 30000,
          'vibes': ['Тайван', 'Хөгжим'],
        };
        respond = (r) async {
          if (r.url.path.endsWith('/get_pilot_overview')) {
            return json(r, {
              'creator_count': 0,
              'venues': 0,
              'content': 0,
              'activated': 0,
              'first_day_followed': 0,
              'first_day_saved': 0,
              'activation_eligible': 0,
              'd7_returned': 0,
              'd7_eligible': 0,
              'repeat_creators': 0,
              'directions': 0,
              'creators': [],
              'participants': [],
              'places': [],
              'posts': [],
            });
          }
          if (r.url.path.endsWith('/venue_catalog')) {
            return json(
                r,
                r.headers['accept']?.contains('vnd.pgrst.object') == true
                    ? venue
                    : [venue]);
          }
          if (r.url.path.endsWith('/place_collections')) {
            return json(r, [
              {
                'id': 'fixture-list',
                'title': 'Шалгалтын урт нэртэй цуглуулга',
                'is_public': true,
                'collection_places': [
                  {
                    'venue_ref': venue['ref'],
                    'venue_catalog': venue,
                    'note': ''
                  }
                ]
              }
            ]);
          }
          return json(r, []);
        };
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ProviderScope(
            overrides: [sessionUserIdProvider.overrideWithValue(me)],
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: child!),
                home: screen.value())));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });
    }
  }
}
