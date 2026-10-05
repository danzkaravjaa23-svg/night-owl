import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/widgets/mobile_frame.dart';
import 'package:night_owl_ub/core/widgets/tonight_card.dart';

void main() {
  for (final width in [320.0, 420.0, 1280.0]) {
    for (final dark in [true, false]) {
      testWidgets('Discovery at $width, dark=$dark, large text', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        AppColors.isDarkMode = dark;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          AppColors.isDarkMode = true;
        });
        final router = GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [TonightCard()])))),
          GoRoute(path: '/explore', builder: (_, __) => const Scaffold(
            body: Text('Discovery destination'))),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: MobileFrame(child: child!)),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cardWidth = tester.getSize(find.descendant(
          of: find.byType(TonightCard), matching: find.byType(Container)).first).width;
        // Desktop frame has a one-pixel border on each side.
        expect(cardWidth, width > 520 ? 378.0 : width - 40);
        await tester.tap(find.text('Газрууд нээх'));
        await tester.pumpAndSettle();
        expect(find.text('Discovery destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
