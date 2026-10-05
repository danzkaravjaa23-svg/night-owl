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
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/events/providers/event_provider.dart';
import 'package:night_owl_ub/features/feed/providers/saved_provider.dart';
import 'package:night_owl_ub/features/feed/providers/stories_provider.dart';
import 'package:night_owl_ub/features/feed/screens/feed_screen.dart';
import 'package:night_owl_ub/features/notifications/providers/notification_provider.dart';
import 'package:night_owl_ub/core/widgets/tonight_card.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test-only-anon-key',
      debug: false,
      httpClient: MockClient((request) async {
        final rows = request.url.path.endsWith('/posts')
            ? [
                for (final author in ['alpha', 'beta'])
                  {
                    'id': 'post-$author',
                    'user_id': author,
                    'caption': 'fixture caption $author',
                    'created_at': DateTime.now().toUtc().toIso8601String(),
                    'likes_count': 12345,
                    'comments_count': 23456,
                    'profiles': {'id': author, 'username': 'fixture_$author'},
                  },
              ]
            : [];
        return http.Response(jsonEncode(rows), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
    );
  });
  tearDown(() async => Supabase.instance.dispose());

  Future<GoRouter> render(WidgetTester tester, double width,
      {Brightness brightness = Brightness.dark}) async {
    AppColors.isDarkMode = brightness == Brightness.dark;
    addTearDown(() => AppColors.isDarkMode = true);
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(initialLocation: '/feed', routes: [
      GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
      for (final path in ['/reels', '/notifications', '/dm', '/story/create'])
        GoRoute(
            path: path,
            builder: (_, __) => Scaffold(body: Text('destination $path'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue(null),
          currentProfileProvider.overrideWith((_) async => null),
          storiesProvider.overrideWith((_) async => []),
          savedPostIdsProvider.overrideWith((_) async => {}),
          feedFollowingIdsProvider.overrideWith((_) async => {'beta'}),
          upcomingEventsProvider.overrideWith((_) async => []),
          unreadNotifCountProvider.overrideWithValue(0),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
        )));
    await tester.pumpAndSettle();
    return router;
  }

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 420.0]) {
      testWidgets(
          'Social at $width in $brightness supports following filter with large text',
          (tester) async {
        await render(tester, width, brightness: brightness);
        expect(
            tester
                .widget<Scaffold>(find.byType(Scaffold).first)
                .backgroundColor,
            brightness == Brightness.dark
                ? AppColors.bgBaseDark
                : AppColors.bgBaseLight);
        expect(tester.takeException(), isNull);
        expect(find.byType(TonightCard), findsNothing);
        expect(find.text('Таны story'), findsOneWidget);
        expect(find.textContaining('fixture caption alpha', findRichText: true),
            findsWidgets);
        await tester.tap(find.byTooltip('Нийтлэлийн шүүлтүүр'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Дагаж буй'));
        await tester.pumpAndSettle();
        expect(find.textContaining('fixture caption alpha', findRichText: true),
            findsNothing);
        expect(find.textContaining('fixture caption beta', findRichText: true),
            findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Нийтлэлийн шүүлтүүр'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Эвентүүд'));
        await tester.pumpAndSettle();
        expect(find.text('Удахгүй болох эвент одоогоор алга.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('Story add, Reels and notifications retain working navigation',
      (tester) async {
    final router = await render(tester, 320);
    await tester.tap(find.byTooltip('Мэдэгдэл'));
    await tester.pumpAndSettle();
    expect(find.text('destination /notifications'), findsOneWidget);
    router.go('/feed');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Мессеж'));
    await tester.pumpAndSettle();
    expect(find.text('destination /dm'), findsOneWidget);
    router.go('/feed');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('destination /story/create'), findsOneWidget);
    router.go('/feed');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reels'));
    await tester.pumpAndSettle();
    expect(find.text('destination /reels'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
