import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/widgets/gradient_button.dart';
import 'package:night_owl_ub/core/widgets/premium_surface.dart';

// DS-03: one primary button, always a pill, with the sizes, busy semantics
// and disabled state the migration lanes rely on.

Widget _frame(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: Center(child: child)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
    );

/// The painted pill: the outermost AnimatedContainer inside the button.
Finder _pill() => find
    .descendant(
        of: find.byType(GradientButton),
        matching: find.byType(AnimatedContainer))
    .first;

BoxDecoration _decoration(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(_pill()).decoration! as BoxDecoration;

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Primary button is a pill at every size', (tester) async {
    for (final size in GradientButtonSize.values) {
      await tester.pumpWidget(_frame(GradientButton(
        label: 'Нэвтрэх',
        size: size,
        fullWidth: false,
        onPressed: () {},
      )));
      await tester.pumpAndSettle();

      final height = tester.getSize(_pill()).height;
      final radius =
          _decoration(tester).borderRadius!.resolve(TextDirection.ltr);
      for (final corner in [
        radius.topLeft,
        radius.topRight,
        radius.bottomLeft,
        radius.bottomRight,
      ]) {
        expect(corner.x, greaterThanOrEqualTo(height / 2), reason: '$size');
        expect(corner.y, greaterThanOrEqualTo(height / 2), reason: '$size');
      }
      final shape = tester
          .widget<ElevatedButton>(find.byType(ElevatedButton))
          .style!
          .shape!
          .resolve(<WidgetState>{});
      expect(shape, isA<StadiumBorder>(), reason: '$size');
      final sheen = tester.widget<ActionSheen>(find.descendant(
          of: find.byType(GradientButton),
          matching: find.byType(ActionSheen)));
      expect(sheen.radius, greaterThanOrEqualTo(height / 2), reason: '$size');
      expect(_decoration(tester).gradient, AppGradients.primary,
          reason: '$size');
    }
  });

  testWidgets('lg and md keep their minimum heights', (tester) async {
    await tester.pumpWidget(_frame(GradientButton(
      label: 'Үргэлжлүүлэх',
      onPressed: () {},
    )));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GradientButton)).height,
        greaterThanOrEqualTo(52));
    expect(tester.getSize(_pill()).height, greaterThanOrEqualTo(52));

    await tester.pumpWidget(_frame(GradientButton(
      label: 'Дахин оролдох',
      size: GradientButtonSize.md,
      fullWidth: false,
      onPressed: () {},
    )));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GradientButton)).height,
        greaterThanOrEqualTo(44));
    expect(tester.getSize(_pill()).height, greaterThanOrEqualTo(44));
  });

  testWidgets('sm draws a compact pill but keeps a 44 px tap target',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(_frame(GradientButton(
      label: 'Дагах',
      size: GradientButtonSize.sm,
      fullWidth: false,
      onPressed: () => taps++,
    )));
    await tester.pumpAndSettle();

    final target = tester.getRect(find.byType(GradientButton));
    final pill = tester.getRect(_pill());
    expect(target.height, greaterThanOrEqualTo(44));
    expect(target.width, greaterThanOrEqualTo(44));
    expect(pill.height, lessThan(44));
    expect(pill.height, greaterThanOrEqualTo(32));

    // A tap on the transparent margin above the pill still counts.
    expect(target.top, lessThan(pill.top));
    await tester.tapAt(Offset(target.center.dx, target.top + 1));
    await tester.pumpAndSettle();
    expect(taps, 1);

    // Screen readers get one merged node with the full target and the label.
    final node = tester.getSemantics(find.byType(GradientButton));
    expect(node.rect.height, greaterThanOrEqualTo(44));
    expect(node.getSemanticsData().label, contains('Дагах'));
    semantics.dispose();
  });

  testWidgets('busy keeps "<label>: түр хүлээнэ үү" and ignores taps',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    for (final size in GradientButtonSize.values) {
      await tester.pumpWidget(_frame(GradientButton(
        label: 'Хадгалах',
        size: size,
        busy: true,
        onPressed: () => taps++,
      )));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Хадгалах: түр хүлээнэ үү'), findsWidgets,
          reason: '$size');
      // What a screen reader announces for the button (merged for sm).
      expect(
          tester
              .getSemantics(find.byType(ElevatedButton))
              .getSemanticsData()
              .label,
          contains('Хадгалах: түр хүлээнэ үү'),
          reason: '$size');
      expect(find.text('Хадгалах'), findsOneWidget, reason: '$size');
      expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNull,
          reason: '$size');
      // Busy still looks like the primary action, not like a disabled one.
      expect(_decoration(tester).gradient, AppGradients.primary,
          reason: '$size');
      await tester.tap(find.byType(GradientButton), warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(taps, 0);
    semantics.dispose();
  });

  testWidgets('is disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(_frame(const GradientButton(label: 'Илгээх')));
    await tester.pumpAndSettle();
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.enabled, isFalse);
    expect(button.onPressed, isNull);
    expect(_decoration(tester).gradient, isNot(AppGradients.primary));
    await tester.tap(find.byType(GradientButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Secondary OutlineButton is a pill as well', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_frame(OutlineButton(
      label: 'Болих',
      onPressed: () => taps++,
    )));
    await tester.pumpAndSettle();
    final box = find.descendant(
        of: find.byType(OutlineButton), matching: find.byType(DecoratedBox));
    final decoration =
        tester.widget<DecoratedBox>(box.first).decoration as BoxDecoration;
    final height = tester.getSize(box.first).height;
    expect(height, greaterThanOrEqualTo(52));
    expect(
        decoration.borderRadius!.resolve(TextDirection.ltr).topLeft.x,
        greaterThanOrEqualTo(height / 2));
    final shape = tester
        .widget<TextButton>(find.byType(TextButton))
        .style!
        .shape!
        .resolve(<WidgetState>{});
    expect(shape, isA<StadiumBorder>());
    await tester.tap(find.text('Болих'));
    expect(taps, 1);
  });

  testWidgets('Compact OutlineButton fits a row next to a compact primary',
      (tester) async {
    var follows = 0;
    var unfollows = 0;
    await tester.pumpWidget(_frame(Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GradientButton(
          label: 'Дагах',
          size: GradientButtonSize.sm,
          fullWidth: false,
          onPressed: () => follows++,
        ),
        const SizedBox(width: 8),
        OutlineButton(
          label: 'Дагасан',
          size: GradientButtonSize.sm,
          fullWidth: false,
          onPressed: () => unfollows++,
        ),
      ],
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final pill = find.descendant(
        of: find.byType(OutlineButton), matching: find.byType(DecoratedBox));
    final painted = tester.getSize(pill.first);
    // Same 36 px look as GradientButton.sm, and only as wide as its label.
    expect(painted.height, closeTo(36, 0.5));
    expect(painted.width, lessThan(200));
    // The tap target still reaches 44 px.
    expect(tester.getSize(find.byType(OutlineButton)).height,
        greaterThanOrEqualTo(44));

    final rect = tester.getRect(pill.first);
    // A tap just above the painted pill (inside the 44 px target) still counts.
    await tester.tapAt(Offset(rect.center.dx, rect.top - 3));
    expect(unfollows, 1);
    await tester.tap(find.text('Дагах'));
    expect(follows, 1);
  });

  testWidgets('OutlineButton md keeps a 44 px minimum and content width',
      (tester) async {
    await tester.pumpWidget(_frame(OutlineButton(
      label: 'Хуваалцах',
      size: GradientButtonSize.md,
      fullWidth: false,
      onPressed: () {},
    )));
    await tester.pumpAndSettle();
    final pill = find.descendant(
        of: find.byType(OutlineButton), matching: find.byType(DecoratedBox));
    final size = tester.getSize(pill.first);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, lessThan(300));
  });
}
