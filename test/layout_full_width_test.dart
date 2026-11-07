// Regression tests for the "loose body shrink-wrap" bug class (see the splash
// fix in ea679bb). Scaffold, Stack and M3 bottom sheets hand their content a
// loose size, so content that does not force full width collapses to its
// widest line and sits in the top-left of the screen (or, for a Stack, takes
// the full height and centres a top bar vertically).
//
// flutter_test's default font draws every glyph as a fontSize-wide square,
// which makes text far wider than on a device and hides the bug. Every test
// here therefore loads the app's real bundled fonts first and checks that it
// did, then measures at an iPhone 15/16 size: 393x852pt at 3x with the
// Dynamic Island / home-indicator insets.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_owl_ub/core/theme/app_text_styles.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/widgets/night_owl_scaffold.dart';
import 'package:night_owl_ub/features/auth/screens/login_screen.dart';
import 'package:night_owl_ub/features/auth/screens/register_screen.dart';
import 'package:night_owl_ub/features/auth/services/auth_provider_settings.dart';
import 'package:night_owl_ub/features/auth/widgets/auth_provider_options.dart';
import 'package:night_owl_ub/features/dm/screens/group_thread_screen.dart';
import 'package:night_owl_ub/features/live/screens/live_viewer_screen.dart';
import 'package:night_owl_ub/features/map/screens/venue_reviews_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _screenWidth = 393.0;
const _screenHeight = 852.0;
const _topInset = 59.0;
const _bottomInset = 34.0;

const _userA = '10000000-0000-4000-8000-000000000001';
const _userB = '10000000-0000-4000-8000-000000000002';
const _peer = '10000000-0000-4000-8000-000000000003';
const _group = '20000000-0000-4000-8000-000000000001';
const _live = '40000000-0000-4000-8000-000000000001';
const _venue = '30000000-0000-4000-8000-000000000001';

const _bundledFonts = {
  'Inter': [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
    'Inter-ExtraBold.ttf',
  ],
  'JetBrainsMono': ['JetBrainsMono-Regular.ttf'],
  'Manrope': ['Manrope-ExtraBold.ttf'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String account;
  late int login;
  Future<http.Response?> Function(http.Request)? route;

  http.Response json(http.Request r, Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: r, headers: {'content-type': 'application/json'});

  Future<void> signIn(String id) async {
    account = id;
    ++login;
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
  }

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Plain family names, for styles that name a bundled family directly.
    for (final entry in _bundledFonts.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    }
    // The google_fonts variant families (Inter_regular, Inter_600, ...) used
    // by AppTheme and AppTextStyles resolve to the same bundled files.
    await GoogleFonts.pendingFonts([
      ...AppTheme.dark.textTheme.apply().toStyles(),
      AppTextStyles.displayMd,
      AppTextStyles.h1,
      AppTextStyles.h2,
      AppTextStyles.h3,
      AppTextStyles.bodyLg,
      AppTextStyles.bodyMd,
      AppTextStyles.bodySm,
      AppTextStyles.bodyXs,
      AppTextStyles.labelLg,
      AppTextStyles.labelMd,
      AppTextStyles.labelSm,
      AppTextStyles.sectionLabel,
      AppTextStyles.monoSm,
      AppTextStyles.btn,
      AppTextStyles.btnSm,
    ]).timeout(const Duration(seconds: 10));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    account = _userA;
    login = 0;
    route = null;
    await Supabase.initialize(
        url: 'https://layout.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((r) async {
          if (r.url.path == '/auth/v1/token') {
            final payload = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': account,
                  'login': login,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                })))
                .replaceAll('=', '');
            return json(r, {
              'access_token': 'fixture.$payload.fixture',
              'refresh_token': 'fixture-refresh-$login',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': account,
                'aud': 'authenticated',
                'created_at': '2026-11-03T00:00:00Z',
              },
            });
          }
          return await route?.call(r) ?? json(r, []);
        }));
  });
  tearDown(() async => Supabase.instance.dispose());

  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(_screenWidth * 3, _screenHeight * 3);
    tester.view.devicePixelRatio = 3;
    const insets =
        FakeViewPadding(top: _topInset * 3, bottom: _bottomInset * 3);
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    addTearDown(tester.view.reset);
  }

  Widget app({Widget? home, GoRouter? router}) {
    Widget builder(BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!);
    return router == null
        ? MaterialApp(theme: AppTheme.dark, builder: builder, home: home)
        : MaterialApp.router(
            theme: AppTheme.dark, builder: builder, routerConfig: router);
  }

  /// The global rect of the glyphs actually painted for [text].
  Rect ink(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.text(text),
        matching: find.byType(RichText),
        matchRoot: true));
    final boxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: 0, extentOffset: paragraph.text.toPlainText().length));
    var rect = boxes.first.toRect();
    for (final box in boxes.skip(1)) {
      rect = rect.expandToInclude(box.toRect());
    }
    return rect.shift(paragraph.localToGlobal(Offset.zero));
  }

  void expectFullWidth(Rect rect, {String? reason}) {
    expect(rect.left, moreOrLessEquals(0, epsilon: 0.5), reason: reason);
    expect(rect.width, moreOrLessEquals(_screenWidth, epsilon: 0.5),
        reason: reason);
  }

  for (final screen in ['login', 'register']) {
    testWidgets(
        '$screen: provider-check status and retry are centred in the sheet, '
        'and the sheet docks to the bottom edge', (tester) async {
      usePhone(tester);
      // A provider check that never answers shows the loading line, then the
      // 12s timeout shows the error block.
      final settingsClient =
          MockClient((_) => Completer<http.Response>().future);
      addTearDown(settingsClient.close);
      final router = GoRouter(initialLocation: '/auth/$screen', routes: [
        GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
            path: '/auth/register',
            builder: (_, __) => const RegisterScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(AuthProviderSettingsScope(
          settings: AuthProviderSettings(client: settingsClient),
          child: app(router: router)));
      await tester.pump(const Duration(seconds: 1));

      final form = tester.getRect(find.byType(Form));
      const status = 'Нэвтрэх нэмэлт аргуудыг шалгаж байна…';
      final statusInk = ink(tester, status);
      // Real fonts: the line fits on one line (~299pt). The test font would
      // make it 504pt and wrap, which hides the shrink-wrap.
      expect(statusInk.height, lessThan(24), reason: 'real fonts not loaded');
      expect(statusInk.width, lessThan(330), reason: 'real fonts not loaded');
      expect(tester.getRect(find.byType(AuthProviderOptions)).width,
          moreOrLessEquals(form.width, epsilon: 0.5));
      expect(statusInk.center.dx, moreOrLessEquals(form.center.dx, epsilon: 1));

      // The glass sheet reaches the screen edge; its footer clears the
      // home indicator.
      final sheet = tester.getRect(find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_GlassSheet'));
      expect(sheet.bottom, moreOrLessEquals(_screenHeight, epsilon: 0.5));
      final footer =
          screen == 'login' ? 'Шинэ хэрэглэгч үү? ' : 'Бүртгэлтэй юу? ';
      expect(tester.getRect(find.text(footer)).bottom,
          lessThanOrEqualTo(_screenHeight - _bottomInset - 16 + 0.5));

      await tester.pump(const Duration(seconds: 13));
      await tester.pump();
      final errorInk = ink(tester, 'Apple, Google нэвтрэлтийг шалгаж чадсангүй.');
      expect(errorInk.center.dx, moreOrLessEquals(form.center.dx, epsilon: 1));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('auth-providers-retry')))
              .center
              .dx,
          moreOrLessEquals(form.center.dx, epsilon: 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('NightOwlScaffold fills the screen around a short body',
      (tester) async {
    usePhone(tester);
    await tester.pumpWidget(app(
        home: const NightOwlScaffold(
            body: Padding(
                padding: EdgeInsets.all(24),
                child: Column(children: [
                  Text('Night Owl'),
                  Text('Оройн газрууд'),
                ])))));
    await tester.pump();
    final stack = find
        .descendant(of: find.byType(Scaffold), matching: find.byType(Stack))
        .first;
    final rect = tester.getRect(stack);
    expectFullWidth(rect);
    expect(rect.height, moreOrLessEquals(_screenHeight, epsilon: 0.5));
    final aurora = find.descendant(
        of: stack,
        matching: find.byWidgetPredicate((w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_AuroraPainter'));
    expectFullWidth(tester.getRect(aurora));
  });

  testWidgets('LiveViewerScreen fills the screen with its top bar at the top',
      (tester) async {
    usePhone(tester);
    route = (r) async {
      final path = r.url.path;
      if (path.endsWith('/live_streams')) {
        return json(r, [
          {
            'id': _live,
            'user_id': _peer,
            'title': 'Friday set',
            'viewer_count': 12,
            'is_live': true,
            'venue_id': null,
          }
        ]);
      }
      if (path.endsWith('/profiles')) {
        return json(r, [
          {'id': _peer, 'username': 'dj_owl', 'avatar_url': null}
        ]);
      }
      if (path.contains('/rpc/')) return json(r, null);
      return null;
    };
    await tester.pumpWidget(app(home: const LiveViewerScreen(liveId: _live)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('dj_owl'), findsWidgets);

    final body = find
        .descendant(of: find.byType(Scaffold), matching: find.byType(Stack))
        .first;
    final rect = tester.getRect(body);
    expectFullWidth(rect);
    expect(rect.height, moreOrLessEquals(_screenHeight, epsilon: 0.5));
    // Top bar: SafeArea top + 8pt padding + a 40pt button. Before the fix
    // the bar was centred vertically (back button at y≈422).
    final back = tester.getRect(find.byIcon(Icons.arrow_back_ios_new));
    expect(back.top, greaterThanOrEqualTo(_topInset));
    expect(back.bottom, lessThanOrEqualTo(_topInset + 8 + 40 + 0.5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final addMember in [false, true]) {
    final sheetName = addMember ? 'add-member' : 'members';
    testWidgets('group $sheetName sheet stays full width after an account switch',
        (tester) async {
      usePhone(tester);
      route = (r) async {
        final path = r.url.path;
        if (path.endsWith('/group_chats')) {
          return json(r, {'name': 'Night crew'});
        }
        if (path.endsWith('/group_members') && r.method == 'GET') {
          return json(r, [
            {
              'user_id': _peer,
              'profiles': {'id': _peer, 'username': 'member_peer'}
            }
          ]);
        }
        if (path.endsWith('/group_messages') && r.method == 'GET') {
          return json(r, []);
        }
        if (path.endsWith('/profiles')) {
          return json(r, [
            {'id': _userB, 'username': 'candidate'}
          ]);
        }
        return json(r, null);
      };
      await signIn(_userA);
      final container = ProviderContainer();
      final router = GoRouter(initialLocation: '/group', routes: [
        GoRoute(
            path: '/group',
            builder: (_, __) => const GroupThreadScreen(groupId: _group)),
        GoRoute(
            path: '/dm',
            builder: (_, __) => const Scaffold(body: Text('Inbox'))),
      ]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        container.dispose();
      });
      // The visible sheet is the Material inside BottomSheet; BottomSheet
      // itself centres it in a full-width Align.
      Finder sheetSurface() => find
          .descendant(
              of: find.byType(BottomSheet), matching: find.byType(Material))
          .first;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: app(router: router)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Night crew'));
      await tester.pumpAndSettle();
      if (addMember) {
        await tester.tap(find.text('Гишүүн нэмэх'));
        await tester.pumpAndSettle();
      }
      expectFullWidth(tester.getRect(sheetSurface()));

      await signIn(_userB);
      await tester.pumpAndSettle();
      const stale = 'Нэвтрэх хаяг өөрчлөгдсөн байна.';
      expect(find.text(stale), findsOneWidget);
      // Before the fix the sheet shrank to a ~287pt card around the message.
      expectFullWidth(tester.getRect(sheetSurface()));
      expect(ink(tester, stale).center.dx,
          moreOrLessEquals(_screenWidth / 2, epsilon: 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('venue loading skeleton is full width with a reachable back button',
      (tester) async {
    usePhone(tester);
    final gate = Completer<http.Response>();
    route = (r) async {
      if (r.url.path.endsWith('/venues')) return gate.future;
      return null;
    };
    await tester.pumpWidget(ProviderScope(
        child: app(home: const VenueDetailScreen(venueId: _venue))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget);
    expectFullWidth(tester.getRect(scroll));
    final back = tester.getRect(find.byTooltip('Буцах'));
    expect(back.left, lessThan(60));
    expect(back.top, greaterThanOrEqualTo(_topInset));
    expect(back.bottom, lessThan(_topInset + 8 + 56));

    gate.complete(http.Response('[]', 200,
        headers: {'content-type': 'application/json'}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

extension on TextTheme {
  /// Every style of the theme, so their google_fonts variants are loaded.
  List<TextStyle> toStyles() => [
        displayLarge,
        displayMedium,
        displaySmall,
        headlineLarge,
        headlineMedium,
        headlineSmall,
        titleLarge,
        titleMedium,
        titleSmall,
        bodyLarge,
        bodyMedium,
        bodySmall,
        labelLarge,
        labelMedium,
        labelSmall,
      ].whereType<TextStyle>().toList();
}
