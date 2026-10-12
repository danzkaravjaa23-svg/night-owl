import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/widgets/app_motion.dart';
import 'package:night_owl_ub/core/widgets/premium_surface.dart';
import 'package:night_owl_ub/core/widgets/navigation_spotlight.dart';
import 'package:night_owl_ub/core/widgets/theme_reveal.dart';

Widget fixture(Widget child, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('an unused theme reveal can be removed safely', (tester) async {
    await tester.pumpWidget(
        fixture(const ThemeReveal(child: SizedBox(width: 100, height: 100))));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion immediately stops a moving navigation light',
      (tester) async {
    Widget light(int index) => SizedBox(
        width: 366,
        height: 72,
        child: NavigationSpotlight(selectedIndex: index));
    await tester.pumpWidget(fixture(light(0)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(fixture(light(4)));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(fixture(light(4), reduced: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light sweep preserves one activation and becomes idle',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(fixture(ActionSheen(
      child: ElevatedButton(
          onPressed: () => taps++, child: const Text('Хадгалах')),
    )));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Хадгалах')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to reduced motion cancels an active sweep',
      (tester) async {
    final button = ActionSheen(
        child: ElevatedButton(onPressed: () {}, child: const Text('Товч')));
    await tester.pumpWidget(fixture(button));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Товч')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(fixture(button, reduced: true));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion reveals content immediately and keeps it usable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(fixture(
        AppEntrance(
            index: 3,
            child: ActionSheen(
              child: ElevatedButton(
                  onPressed: () => taps++, child: const Text('Нээх')),
            )),
        reduced: true));
    await tester.tap(find.text('Нээх'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
