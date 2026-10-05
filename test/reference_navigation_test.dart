import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/shell/main_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test-only-anon-key',
      debug: false,
      httpClient: MockClient((request) async => http.Response('[]', 200)),
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage()),
    );
  });
  tearDown(() async => Supabase.instance.dispose());

  for (final width in [320.0, 420.0]) {
    testWidgets(
        'Reference footer keeps every destination at $width and large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(initialLocation: '/feed', routes: [
        ShellRoute(builder: (_, __, child) => MainShell(child: child), routes: [
          for (final path in ['/feed', '/explore', '/dm', '/profile'])
            GoRoute(
                path: path,
                builder: (_, __) => Scaffold(body: Text('destination $path'))),
        ]),
        for (final path in [
          '/post/create',
          '/story/create',
          '/reels/create',
          '/event/create'
        ])
          GoRoute(
              path: path,
              builder: (_, __) => Scaffold(body: Text('destination $path'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
      )));
      await tester.pumpAndSettle();
      final labels = ['Газрууд', 'Нийтлэл', 'Мессеж', 'Профайл'];
      final positions = [
        for (final label in labels) tester.getCenter(find.text(label)).dx
      ];
      expect(positions, orderedEquals([...positions]..sort()));
      for (final entry in {
        'Газрууд': '/explore',
        'Мессеж': '/dm',
        'Профайл': '/profile',
        'Нийтлэл': '/feed'
      }.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.text('destination ${entry.value}'), findsOneWidget);
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Шинээр үүсгэх'));
      await tester.pumpAndSettle();
      final story = find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Story'));
      await tester.ensureVisible(story);
      await tester.tap(story);
      await tester.pumpAndSettle();
      expect(find.text('destination /story/create'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
