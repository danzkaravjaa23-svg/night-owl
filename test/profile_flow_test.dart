import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/features/feed/providers/stories_provider.dart';
import 'package:night_owl_ub/features/profile/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const me = 'profile-owner';
  var signedIn = me;
  late List<http.Request> requests;
  late List<Map<String, dynamic>> posts;
  Future<http.Response> Function(http.Request)? postReply;
  Future<http.Response> Function(http.Request)? uploadReply;
  var refuseCoverWrite = false;
  http.Response response(http.Request request, Object? body,
          [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: request, headers: {'content-type': 'application/json'});
  Map<String, dynamic> post(String id) => {
        'id': id,
        'user_id': me,
        'media_url': null,
        'likes_count': 0,
        'created_at': '2026-11-03T00:00:00Z',
      };
  Future<void> signIn([String owner = me]) async {
    signedIn = owner;
    await Supabase.instance.client.auth.signInWithPassword(
        email: '$owner@example.test', password: 'fixture-only-password');
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    requests = [];
    posts = [];
    await Supabase.initialize(
        url: 'https://profile-fixture.example.test',
        anonKey: 'fixture-only-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path == '/auth/v1/token') {
            final payload = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': signedIn,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                })))
                .replaceAll('=', '');
            return response(request, {
              'access_token': 'fixture.$payload.fixture',
              'refresh_token': 'fixture-refresh',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': signedIn,
                'aud': 'authenticated',
                'created_at': '2026-11-03T00:00:00Z',
              },
            });
          }
          if (path == '/rest/v1/profiles') {
            if (request.method == 'PATCH') {
              return response(
                  request, refuseCoverWrite ? null : {'id': signedIn});
            }
            return response(request, [
              {'id': signedIn, 'username': signedIn, 'full_name': 'Fixture Owl'}
            ]);
          }
          if (path == '/rest/v1/posts') {
            if (postReply != null) return postReply!(request);
            return response(request, posts);
          }
          if (path.startsWith('/storage/v1/object/avatars/')) {
            if (uploadReply != null) return uploadReply!(request);
            return response(request, {'Key': path});
          }
          return response(request, []);
        }));
  });
  setUp(() async {
    requests = [];
    posts = [];
    postReply = null;
    uploadReply = null;
    refuseCoverWrite = false;
    await signIn();
    requests.clear();
  });
  tearDown(() => AppColors.isDarkMode = true);
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> render(WidgetTester tester,
      {Future<Uint8List?> Function()? picker,
      Size size = const Size(390, 900),
      double scale = 1,
      bool dark = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    AppColors.isDarkMode = dark;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(initialLocation: '/profile', routes: [
      GoRoute(
          path: '/profile',
          builder: (_, __) => ProfileScreen(coverPicker: picker)),
      GoRoute(
          path: '/post/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Post ${state.pathParameters['id']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [storiesProvider.overrideWith((_) async => [])],
        child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
  }

  Finder cover() => find.byTooltip('Нүүр зураг солих');
  Finder tiles() => find.descendant(
      of: find.byType(SliverGrid), matching: find.byType(GestureDetector));
  Iterable<http.Request> uploads() => requests
      .where((r) => r.url.path.startsWith('/storage/v1/object/avatars/'));
  Iterable<http.Request> patches() => requests
      .where((r) => r.url.path == '/rest/v1/profiles' && r.method == 'PATCH');
  Future<void> tick(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
  }

  testWidgets('cover picker is single-flight and cancel restores controls',
      (tester) async {
    final pending = Completer<Uint8List?>();
    var calls = 0;
    await render(tester, picker: () {
      calls++;
      return pending.future;
    });
    await tester.tap(cover());
    await tester.tap(cover());
    await tester.pump();
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(uploads(), isEmpty);
    expect(patches(), isEmpty);
    await tester.tap(cover());
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('picker failure is visible and retryable', (tester) async {
    var calls = 0;
    await render(tester, picker: () async {
      calls++;
      if (calls == 1) throw StateError('fixture picker unavailable');
      return null;
    });
    await tester.tap(cover());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Нүүр зураг хадгалж чадсангүй'), findsOneWidget);
    await tester.tap(cover());
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('account switch during picker prevents old-account upload',
      (tester) async {
    final pending = Completer<Uint8List?>();
    await render(tester, picker: () => pending.future);
    await tester.tap(cover());
    await signIn('second-owner');
    await tester.pumpAndSettle();
    pending.complete(image.encodePng(image.Image(width: 2, height: 2)));
    for (var i = 0; i < 5; i++) {
      await tick(tester);
    }
    await tester.pumpAndSettle();
    expect(uploads(), isEmpty);
    expect(patches(), isEmpty);
    expect(find.text('Нүүр зураг хадгалж чадсангүй'), findsNothing);
  });

  testWidgets('account switch during upload prevents old-account profile write',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? upload;
    uploadReply = (request) {
      upload = request;
      return pending.future;
    };
    await render(tester,
        picker: () async => image.encodePng(image.Image(width: 2, height: 2)));
    await tester.tap(cover());
    for (var i = 0; i < 30 && upload == null; i++) {
      await tick(tester);
    }
    expect(upload, isNotNull);
    await signIn('second-owner');
    await tester.pump();
    pending.complete(response(upload!, {'Key': upload!.url.path}));
    await tester.pumpAndSettle();
    expect(patches(), isEmpty);
    expect(find.text('Нүүр зураг хадгалж чадсангүй'), findsNothing);
  });

  testWidgets(
      'failed refresh retries from the first page even after end of list',
      (tester) async {
    posts = [post('first-post')];
    await render(tester);
    var failed = true;
    postReply = (request) async => failed
        ? response(request, {'message': 'offline', 'code': 'XX000'}, 400)
        : response(request, [post('fresh-post')]);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(tiles(), findsOneWidget);
    final before = requests.where((r) => r.url.path == '/rest/v1/posts').length;
    failed = false;
    await tester.ensureVisible(find.text('Дахин оролдох'));
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.url.path == '/rest/v1/posts').length,
        before + 1);
    expect(find.text('Дахин оролдох'), findsNothing);
    await tester.tap(tiles().first);
    await tester.pumpAndSettle();
    expect(find.text('Post fresh-post'), findsOneWidget);
  });

  testWidgets('confirmed deletion wins over an already pending refresh',
      (tester) async {
    final original = post('deleted-post');
    posts = [original];
    await render(tester);
    final pending = Completer<http.Response>();
    http.Request? refreshRequest;
    postReply = (request) async {
      if (request.method == 'DELETE') return response(request, [original]);
      if (refreshRequest == null) {
        refreshRequest = request;
        return pending.future;
      }
      return response(request, []);
    };
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    await tester.longPress(tiles().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Устгах'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE').length, 1);
    pending.complete(response(refreshRequest!, [original]));
    await refresh;
    await tester.pumpAndSettle();
    expect(tiles(), findsNothing);
    expect(find.text('Эхний нийтлэлээ нэмээрэй'), findsOneWidget);
  });

  for (final refused in [false, true]) {
    testWidgets('cover save requires a confirmed profile row refused=$refused',
        (tester) async {
      refuseCoverWrite = refused;
      await render(tester,
          picker: () async =>
              image.encodePng(image.Image(width: 2, height: 2)));
      final reads = requests
          .where((r) => r.url.path == '/rest/v1/profiles' && r.method == 'GET')
          .length;
      await tester.tap(cover());
      for (var i = 0; i < 30 && patches().isEmpty; i++) {
        await tick(tester);
      }
      await tester.pumpAndSettle();
      expect(uploads(), hasLength(1));
      expect(patches(), hasLength(1));
      expect(patches().single.url.queryParameters['id'], 'eq.$me');
      final saved = jsonDecode(patches().single.body) as Map;
      expect(saved['cover_url'], contains('/avatars/$me/cover_'));
      expect(find.text('Нүүр зураг хадгалж чадсангүй'),
          refused ? findsOneWidget : findsNothing);
      expect(
          requests
              .where(
                  (r) => r.url.path == '/rest/v1/profiles' && r.method == 'GET')
              .length,
          reads + (refused ? 0 : 1));
    });
  }

  testWidgets('a delete confirmation cannot target the next signed-in account',
      (tester) async {
    posts = [post('old-post')];
    await render(tester);
    await tester.longPress(tiles().first);
    await tester.pumpAndSettle();
    await signIn('second-owner');
    posts = [];
    await tester.pumpAndSettle();
    await tester.tap(find.text('Устгах'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    expect(find.text('Устгагдлаа'), findsNothing);
  });

  testWidgets(
      'pending deletion blocks duplicates and ignores a late response after switching account',
      (tester) async {
    final original = post('old-post');
    posts = [original];
    await render(tester);
    final pending = Completer<http.Response>();
    http.Request? deleting;
    postReply = (request) async {
      if (request.method == 'DELETE') {
        deleting = request;
        return pending.future;
      }
      return response(request, posts);
    };
    await tester.longPress(tiles().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Устгах'));
    await tester.pumpAndSettle();
    await tester.longPress(tiles().first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests.where((r) => r.method == 'DELETE'), hasLength(1));
    await signIn('second-owner');
    posts = [];
    await tester.pumpAndSettle();
    pending.complete(response(deleting!, [original]));
    await tester.pumpAndSettle();
    expect(find.text('Устгагдлаа'), findsNothing);
    expect(requests.where((r) => r.url.path.startsWith('/storage/')), isEmpty);
    expect(tiles(), findsNothing);
  });

  for (final dark in [true, false]) {
    testWidgets(
        'profile actions and empty content fit 320x480 at 1.5x in ${dark ? 'night' : 'day'}',
        (tester) async {
      var picked = 0;
      await render(tester, size: const Size(320, 480), scale: 1.5, dark: dark,
          picker: () async {
        picked++;
        return null;
      });
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(cover());
      await tester.tap(cover());
      await tester.pumpAndSettle();
      expect(picked, 1);
      await tester.scrollUntilVisible(find.text('Хадгалсан'), 150,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Хадгалсан'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Постууд үзэх'), 150,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Постууд үзэх').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
