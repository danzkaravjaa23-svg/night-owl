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
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/theme_provider.dart';
import 'package:night_owl_ub/features/dm/screens/dm_list_screen.dart';
import 'package:night_owl_ub/features/dm/screens/dm_thread_screen.dart';
import 'package:night_owl_ub/features/dm/screens/group_thread_screen.dart';

class _ThemeFixture extends ConsumerWidget {
  final GoRouter router;
  const _ThemeFixture(this.router);
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: ref.watch(themeModeProvider),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test-only-anon-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET',
            reason: 'Layout fixtures must never submit messages or groups');
        final rows = request.url.path.endsWith('/notes')
            ? [
                {
                  'user_id': 'fixture-person',
                  'text': 'Fixture note with enough words to wrap',
                  'venue_id': 'fixture-venue',
                  'created_at': DateTime.now().toUtc().toIso8601String()
                },
              ]
            : request.url.path.endsWith('/profiles')
                ? [
                    {
                      'id': 'fixture-person',
                      'username': 'fixture_person',
                      'avatar_url': null
                    },
                  ]
                : request.url.path.endsWith('/venues')
                    ? [
                        {'id': 'fixture-venue', 'name': 'Fixture venue'}
                      ]
                    : [];
        return http.Response(jsonEncode(rows), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });
  tearDown(() async => Supabase.instance.dispose());

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
        'Messages at 320px in ${mode.name} keeps draft through theme and group actions',
        (tester) async {
      SharedPreferences.setMockInitialValues({'theme_mode': mode.name});
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => AppColors.isDarkMode = true);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const DmListScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(child: _ThemeFixture(router)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'draft search');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(mode == ThemeMode.dark
          ? 'Өдрийн горимд шилжих'
          : 'Шөнийн горимд шилжих'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller?.text, 'draft search');
      expect(
          tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
          mode == ThemeMode.dark
              ? AppColors.bgBaseLight
              : AppColors.bgBaseDark);
      await tester.tap(find.byTooltip('Цэвэрлэх'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);
      await tester.tap(find.byTooltip('Групп чат үүсгэх'));
      await tester.pumpAndSettle();
      expect(find.text('Групп чат үүсгэх'), findsOneWidget);
      expect(find.text('Гишүүн сонгоно уу'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    for (final group in [false, true]) {
      testWidgets(
          '${group ? 'Group' : 'Direct'} thread at 320px in ${mode.name}',
          (tester) async {
        SharedPreferences.setMockInitialValues({'theme_mode': mode.name});
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => AppColors.isDarkMode = true);
        final router = GoRouter(routes: [
          GoRoute(
              path: '/',
              builder: (_, __) => group
                  ? const GroupThreadScreen(
                      groupId: 'fixture-group', groupName: 'Fixture group')
                  : const DmThreadScreen(threadId: 'fixture-person')),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(ProviderScope(child: _ThemeFixture(router)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField).first, 'Unsent draft');
        await tester.tap(find.byTooltip(mode == ThemeMode.dark
            ? 'Өдрийн горимд шилжих'
            : 'Шөнийн горимд шилжих'));
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller
                ?.text,
            'Unsent draft');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
