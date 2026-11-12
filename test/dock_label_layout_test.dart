import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/shell/main_shell.dart';

/// CS-02: footer dock labels stay on one line (never broken mid-word or
/// ellipsized) on narrow screens and with large system text.
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

  const labels = ['Газрууд', 'Нийтлэл', 'Мессеж', 'Профайл'];
  // Dock labels: fontSize 12, height 1.2, text scaling clamped to 1.3x.
  const maxLineHeight = 12 * 1.2 * 1.3;

  for (final width in [320.0, 360.0, 390.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('dock labels stay on one line at $width px, text x$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = GoRouter(initialLocation: '/feed', routes: [
          ShellRoute(
              builder: (_, __, child) => MainShell(child: child),
              routes: [
                for (final path in ['/feed', '/explore', '/dm', '/profile'])
                  GoRoute(
                      path: path,
                      builder: (_, __) =>
                          Scaffold(body: Text('destination $path'))),
              ]),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(ProviderScope(
            child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (final label in labels) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          // Not cut to an ellipsis and not wrapped onto a second line.
          expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          expect(paragraph.size.height, lessThanOrEqualTo(maxLineHeight + .5),
              reason: '$label must be a single line');

          final item = find.ancestor(of: text, matching: find.byType(TextButton));
          expect(item, findsOneWidget);
          final itemRect = tester.getRect(item);
          expect(itemRect.width, greaterThanOrEqualTo(48), reason: label);
          expect(itemRect.height, greaterThanOrEqualTo(44), reason: label);
          // The visible (fitted) label stays inside its own slot.
          final labelRect = tester.getRect(text);
          expect(labelRect.left, greaterThanOrEqualTo(itemRect.left - .5),
              reason: label);
          expect(labelRect.right, lessThanOrEqualTo(itemRect.right + .5),
              reason: label);
          expect(labelRect.bottom, lessThanOrEqualTo(itemRect.bottom + .5),
              reason: label);
        }

        // Labels keep their left-to-right order.
        final positions = [
          for (final label in labels) tester.getCenter(find.text(label)).dx
        ];
        expect(positions, orderedEquals([...positions]..sort()));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
