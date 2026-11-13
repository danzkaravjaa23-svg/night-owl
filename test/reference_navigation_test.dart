import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/widgets/app_sheet.dart';
import 'package:night_owl_ub/features/shell/main_shell.dart';

/// Sends Android's system back through the platform channel.
Future<void> systemBack(WidgetTester tester) async {
  final message =
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
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

  for (final mode in [
    'animated',
    'disableAnimations',
    'accessibleNavigation'
  ]) {
    testWidgets(
        'rapid footer switches finish on Profile and become idle: $mode',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final router = GoRouter(initialLocation: '/feed', routes: [
        ShellRoute(builder: (_, __, child) => MainShell(child: child), routes: [
          for (final path in ['/feed', '/explore', '/dm', '/profile'])
            GoRoute(
                path: path,
                builder: (_, __) => Scaffold(body: Text('destination $path'))),
        ]),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: mode == 'disableAnimations',
                accessibleNavigation: mode == 'accessibleNavigation'),
            child: child!),
      )));
      if (mode != 'animated') {
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      await tester.pumpAndSettle();

      // Switch before the previous selection transition can finish.
      for (final label in ['Газрууд', 'Мессеж', 'Нийтлэл', 'Профайл']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/profile');
      expect(find.text('destination /profile'), findsOneWidget);
      final selectedLabels = tester.semantics
          .simulatedAccessibilityTraversal()
          .where((node) =>
              node.getSemanticsData().flagsCollection.isSelected ==
              Tristate.isTrue)
          .map((node) => node.getSemanticsData().label);
      expect(selectedLabels, orderedEquals(['Профайл']));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  }

  testWidgets(
      'Android back closes a root dialog before the tab page pushed under it',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(initialLocation: '/profile', routes: [
      ShellRoute(builder: (_, __, child) => MainShell(child: child), routes: [
        for (final path in ['/feed', '/profile'])
          GoRoute(
              path: path,
              builder: (_, __) => Scaffold(body: Text('destination $path'))),
        GoRoute(
            path: '/dm',
            builder: (_, __) => Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => const AlertDialog(
                                content: Text('dialog fixture'))),
                        child: const Text('open dialog'))))),
      ]),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    // Like /dm or /reels pushed over a tab: the shell navigator can pop.
    router.push('/dm');
    await tester.pumpAndSettle();
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('dialog fixture'), findsOneWidget);

    // The dialog sits on the root navigator above the shell: back closes it
    // and keeps the page underneath.
    await systemBack(tester);
    expect(find.text('dialog fixture'), findsNothing);
    expect(find.text('open dialog'), findsOneWidget);

    // Then back pops the pushed page, and a tab root goes back to Feed.
    await systemBack(tester);
    expect(find.text('open dialog'), findsNothing);
    expect(find.text('destination /profile'), findsOneWidget);
    await systemBack(tester);
    expect(find.text('destination /feed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final dark in [true, false]) {
    testWidgets(
        'Create sheet has one handle, covers the dock and closes itself '
        '(${dark ? 'Night' : 'Day'})', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => AppColors.isDarkMode = true);
      AppColors.isDarkMode = dark;
      final router = GoRouter(initialLocation: '/feed', routes: [
        ShellRoute(builder: (_, __, child) => MainShell(child: child), routes: [
          for (final path in ['/feed', '/profile'])
            GoRoute(
                path: path,
                builder: (_, __) => Scaffold(body: Text('destination $path'))),
        ]),
        GoRoute(
            path: '/story/create',
            builder: (_, __) =>
                const Scaffold(body: Text('destination /story/create'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp.router(
              theme: dark ? AppTheme.dark : AppTheme.light,
              routerConfig: router)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Шинээр үүсгэх'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      // DS-02: only the theme's drag handle (36×4), no hand-drawn second one.
      final handles = find
          .descendant(
              of: sheet,
              matching: find.byWidgetPredicate((w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).borderRadius != null))
          .evaluate()
          .where((element) {
        final box = element.renderObject;
        return box is RenderBox &&
            box.hasSize &&
            box.size.height == 4 &&
            box.size.width >= 30 &&
            box.size.width <= 48;
      });
      expect(handles, hasLength(1));
      expect(find.descendant(of: sheet, matching: find.byType(AppSheetHeader)),
          findsOneWidget);
      // The sheet's scrim covers the dock.
      expect(find.text('Профайл').hitTestable(), findsNothing);

      await tester
          .tap(find.descendant(of: sheet, matching: find.text('Story')));
      await tester.pumpAndSettle();
      expect(find.text('destination /story/create'), findsOneWidget);
      // The option closed the sheet itself: going back shows the tab, not a
      // sheet left open under the new page.
      await systemBack(tester);
      expect(find.text('destination /feed'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
