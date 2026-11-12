import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/constants/app_constants.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/feed/screens/story_viewer_screen.dart';
import 'package:night_owl_ub/models/story.dart';
import 'package:night_owl_ub/models/user_profile.dart';

// MO-01 / MO-06: the owner's phone runs with every system animation scale at
// 0, so Flutter reports disableAnimations = true. The story timer must still
// measure real time, and a single tap must act at once (no double-tap wait).

const _author = 'fixture-author';
const _viewer = 'fixture-viewer';

Story _story(String id, String caption) => Story(
      id: id,
      userId: _author,
      // A protected Storage URL keeps the image offline: the signing request
      // goes to the mock client below, fails, and the viewer shows its error
      // tile instead of starting a network image download.
      mediaUrl:
          '${AppConstants.backendUrl}/storage/v1/object/public/stories/$_author/$id.jpg',
      caption: caption,
      duration: 5,
      expiresAt: DateTime.now().add(const Duration(hours: 12)),
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

StoryRing _ring(List<Story> stories) => StoryRing(
      userId: _author,
      author: UserProfile(id: _author, username: 'fixture_author'),
      stories: stories,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<http.Request> likeWrites;

  setUp(() async {
    likeWrites = [];
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test-only-anon-key',
      debug: false,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/auth/v1/token') {
          final payload = base64Url
              .encode(utf8.encode(jsonEncode({
                'sub': _viewer,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              })))
              .replaceAll('=', '');
          return http.Response(
              jsonEncode({
                'access_token': 'fixture.$payload.fixture',
                'refresh_token': 'fixture-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': _viewer,
                  'aud': 'authenticated',
                  'created_at': '2026-11-01T00:00:00Z'
                },
              }),
              200,
              headers: {'content-type': 'application/json'}, request: request);
        }
        if (path == '/rest/v1/story_likes') {
          if (request.method == 'POST' || request.method == 'DELETE') {
            likeWrites.add(request);
            return http.Response('', 201, request: request);
          }
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'},
              request: request);
        }
        return http.Response(
            '{"statusCode":"400","error":"fixture","message":"offline fixture"}',
            400,
            headers: {'content-type': 'application/json'},
            request: request);
      }),
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage()),
    );
    // The viewer toggles immersive mode on open/close.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await Supabase.instance.dispose();
  });

  void disableAnimations(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  final viewer = find.byType(StoryViewerScreen);

  double progress(WidgetTester tester) => tester
      .widget<FractionallySizedBox>(find.descendant(
          of: viewer, matching: find.byType(FractionallySizedBox)))
      .widthFactor!;

  // Opens the viewer as a pushed route (as the app does), so the viewer can
  // close itself after the last story without emptying the navigator.
  Future<void> open(WidgetTester tester, StoryRing ring) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionUserIdProvider.overrideWith((ref) => null)],
      child: MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('fixture-home')),
      ),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => StoryViewerScreen(rings: [ring])));
    // Frame 1 builds the route and starts the progress ticker; frame 2 is
    // the ticker's first tick (elapsed 0). No fake time passes in either.
    await tester.pump();
    await tester.pump();
    expect(viewer, findsOneWidget);
  }

  testWidgets(
      'with system animations off a 5 s story still lasts 5 s before closing',
      (tester) async {
    disableAnimations(tester);
    await open(tester, _ring([_story('only', 'Ганц түүх')]));

    // Before the fix Flutter scaled the timer to 5% (0.25 s): the story
    // was already finished and the viewer closed at this point.
    await tester.pump(const Duration(seconds: 1));
    expect(viewer, findsOneWidget);
    expect(progress(tester), closeTo(0.2, 0.02));

    await tester.pump(const Duration(seconds: 3));
    expect(viewer, findsOneWidget);
    expect(progress(tester), closeTo(0.8, 0.02));

    await tester.pump(const Duration(milliseconds: 900));
    expect(viewer, findsOneWidget, reason: '4.9 s: still showing the story');
    expect(progress(tester), closeTo(0.98, 0.02));

    // Past 5 s the only story completes and the viewer closes itself.
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(viewer, findsNothing);
    expect(find.text('fixture-home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single taps on a story act immediately (no double-tap wait)',
      (tester) async {
    disableAnimations(tester);
    await open(
        tester,
        _ring([
          _story('first', 'Эхний түүх'),
          _story('second', 'Дараагийн түүх'),
        ]));
    await tester.pump(const Duration(milliseconds: 100));

    // The full-screen story detector (tap zones + swipe-down to close) must
    // not listen for double taps: that makes Flutter hold every single tap
    // for ~300 ms.
    final storyDetector = tester
        .widgetList<GestureDetector>(find.descendant(
            of: viewer, matching: find.byType(GestureDetector)))
        .where((d) => d.onTapUp != null && d.onVerticalDragEnd != null)
        .single;
    expect(storyDetector.onDoubleTap, isNull);

    final box = tester.getRect(viewer);
    Offset at(double fx) =>
        Offset(box.left + box.width * fx, box.top + box.height * 0.45);
    expect(find.text('Эхний түүх'), findsOneWidget);

    // Right side → next story, within the same frame (no fake time passes).
    await tester.tapAt(at(0.85));
    await tester.pump();
    expect(find.text('Дараагийн түүх'), findsOneWidget);
    expect(find.text('Эхний түүх'), findsNothing);

    // Centre → pause immediately; the bar does not move while paused.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(at(0.5));
    await tester.pump();
    final paused = progress(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(progress(tester), paused);
    expect(find.text('Дараагийн түүх'), findsOneWidget);

    // Centre again → resume; real time drives the bar (1 s = 20% of 5 s).
    await tester.tapAt(at(0.5));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), closeTo(paused + 0.2, 0.03));

    // Left side → previous story, immediately.
    await tester.tapAt(at(0.15));
    await tester.pump();
    expect(find.text('Эхний түүх'), findsOneWidget);
    expect(find.text('Дараагийн түүх'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('the heart button likes the story without moving to the next',
      (tester) async {
    await tester.runAsync(() => Supabase.instance.client.auth
        .signInWithPassword(
            email: 'viewer@example.test', password: 'fixture-password'));
    disableAnimations(tester);
    await open(
        tester,
        _ring([
          _story('first', 'Эхний түүх'),
          _story('second', 'Дараагийн түүх'),
        ]));
    await tester.pump(const Duration(milliseconds: 100));

    final semantics = tester.ensureSemantics();
    bool? toggled(WidgetTester tester, Finder finder) => tester
        .getSemantics(finder)
        .getSemanticsData()
        .flagsCollection
        .isToggled
        .toBoolOrNull();
    final heart = find.bySemanticsLabel('Таалагдах');
    expect(heart, findsOneWidget);
    expect(toggled(tester, heart), isFalse);

    await tester.tap(heart);
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    expect(likeWrites, hasLength(1));
    expect(likeWrites.single.method, 'POST');
    expect(
        jsonDecode(likeWrites.single.body), containsPair('story_id', 'first'));
    expect(toggled(tester, heart), isTrue);
    // Liking is not a navigation tap: the same story stays on screen.
    expect(find.text('Эхний түүх'), findsOneWidget);
    expect(find.text('Дараагийн түүх'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
