import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/widgets/empty_state.dart';
import 'package:night_owl_ub/core/widgets/eclipse_theme_toggle.dart';
import 'package:night_owl_ub/core/widgets/glass_icon_button.dart';
import 'package:night_owl_ub/core/widgets/gradient_button.dart';

Widget frame(Widget child, {double scale = 1}) => MaterialApp(
      home: Scaffold(body: child),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            disableAnimations: true, textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'Glass icon is reachable by keyboard and disabled does not activate',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(frame(Center(
        child: GlassIconButton(
            icon: Icons.search, tooltip: 'Хайх', onTap: () => taps++))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(GlassIconButton)).shortestSide,
        greaterThanOrEqualTo(44));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.pumpWidget(frame(const Center(
        child: GlassIconButton(icon: Icons.search, tooltip: 'Хайх'))));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.byType(GlassIconButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Theme toggle is keyboard accessible and settles without a ticker',
      (tester) async {
    final previous = EclipseThemeToggle.ambientFlow;
    EclipseThemeToggle.ambientFlow = true;
    addTearDown(() => EclipseThemeToggle.ambientFlow = previous);
    var dark = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child:
          EclipseThemeToggle(isDark: true, onChanged: (value) => dark = value),
    ))));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(dark, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Short viewport and doubled text can scroll to recovery action',
      (tester) async {
    tester.view.physicalSize = const Size(320, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    await tester.pumpWidget(frame(
      EmptyState(
        icon: Icons.wifi_off,
        title: 'Холболтоо шалгаарай',
        subtitle: 'Интернэт холболт сэргэсэн үед дахин оролдоно уу.',
        action: GradientButton(label: 'Дахин оролдох', onPressed: () => taps++),
      ),
      scale: 2,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(GradientButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty state composes inside a parent scroll view',
      (tester) async {
    await tester.pumpWidget(frame(const SingleChildScrollView(
      child: EmptyState(icon: Icons.photo, title: 'Одоогоор нийтлэл алга'),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small primary action has a 44px target and retains busy context',
      (tester) async {
    await tester.pumpWidget(frame(const Center(
        child: GradientButton(
      label: 'Хадгалах',
      size: GradientButtonSize.md,
      busy: true,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Хадгалах'), findsOneWidget);
    expect(tester.getSize(find.byType(GradientButton)).height,
        greaterThanOrEqualTo(44));
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);
  });
}
