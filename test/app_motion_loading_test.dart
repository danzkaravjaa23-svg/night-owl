import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/widgets/app_motion.dart';
import 'package:night_owl_ub/core/widgets/gradient_button.dart';
import 'package:night_owl_ub/core/widgets/owl_loading.dart';
import 'package:night_owl_ub/core/widgets/skeleton.dart';
import 'package:night_owl_ub/core/widgets/mesh_gradient.dart';
import 'package:night_owl_ub/features/auth/widgets/auth_ui.dart';

Widget fixture(Widget child,
        {bool reduced = false,
        bool accessible = false,
        bool ticking = true,
        double scale = 1,
        Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(
            disableAnimations: reduced,
            accessibleNavigation: accessible,
            textScaler: TextScaler.linear(scale)),
        child: TickerMode(
            enabled: ticking, child: Scaffold(body: Center(child: child))),
      ),
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final accessible in [false, true]) {
    testWidgets('auth controls honor reduced motion $accessible', (tester) async {
      var taps = 0;
      await tester.pumpWidget(fixture(AuthEntrance(index: 4, child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [TapScale(onTap: () => taps++, child: const Text('Continue')), const BtnSpinner()],
      )), reduced: !accessible, accessible: accessible));
      await tester.pumpAndSettle();
      final press = await tester.startGesture(tester.getCenter(find.text('Continue')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await press.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.byType(OwlLoading), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('press, release and cancel keep activation with the real control',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(fixture(PressFeedback(
        pressedScale: .94,
        child: ElevatedButton(
            onPressed: () => taps++, child: const Text('Tap')))));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Tap')));
    await tester.pump(AppMotion.press);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .94);
    expect(taps, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    final cancel =
        await tester.startGesture(tester.getCenter(find.text('Tap')));
    await tester.pump(AppMotion.press);
    await cancel.cancel();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  for (final accessible in [false, true]) {
    testWidgets(
        'reduced motion ${accessible ? 'navigation' : 'animation'} stops press and loaders',
        (tester) async {
      await tester.pumpWidget(fixture(
          Column(mainAxisSize: MainAxisSize.min, children: [
            PressFeedback(
                child:
                    ElevatedButton(onPressed: () {}, child: const Text('Tap'))),
            const OwlLoading(),
            const SkeletonBox(width: 80, height: 20),
            const SizedBox(
                width: 80, height: 20, child: MeshGradientBackground())
          ]),
          reduced: !accessible,
          accessible: accessible));
      await tester.pumpAndSettle();
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Tap')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
          Duration.zero);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('busy button is inert and compact owl fits a tiny control',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(fixture(
        Column(mainAxisSize: MainAxisSize.min, children: [
          GradientButton(
              label: 'Хадгалах', busy: true, onPressed: () => taps++),
          const SizedBox(
              width: 18,
              height: 18,
              child: OwlLoading(
                  size: 18, compact: true, message: 'Байршлыг ачаалж байна')),
        ]),
        reduced: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    expect(taps, 0);
    expect(find.text('Хадгалах'), findsNothing);
    expect(find.text('Байршлыг ачаалж байна'), findsNothing);
    expect(tester.getSize(find.byType(OwlLoading).last), const Size(18, 18));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('shared buttons wrap at 248px with large text in $brightness',
        (tester) async {
      await tester.pumpWidget(fixture(
          SizedBox(
              width: 248,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                GradientButton(
                    label: 'Анхны нийтлэлээ хуваалцах',
                    icon: const Icon(Icons.add),
                    onPressed: () {}),
                const SizedBox(height: 16),
                OutlineButton(label: 'Шинээр бүртгэл үүсгэх', onPressed: () {}),
                const SizedBox(height: 16),
                Row(children: [
                  Flexible(
                      child: GradientButton(
                          label: 'Дахин оролдох',
                          fullWidth: false,
                          size: GradientButtonSize.md,
                          onPressed: () {}))
                ]),
              ])),
          scale: 1.5,
          reduced: true,
          brightness: brightness));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(GradientButton).first).height,
          greaterThan(52));
      expect(tester.getSize(find.byType(OutlineButton)).height,
          greaterThanOrEqualTo(52));
    });
  }

  testWidgets(
      'loading blinks, terminal emotions and offstage stop, retry works',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(fixture(const OwlLoading(size: 64)));
    await tester.pump();
    expect(tester.widget<OwlEmotion>(find.byType(OwlEmotion)).mood,
        OwlMood.curious);
    await tester.pump(const Duration(milliseconds: 2950));
    expect(
        tester.widget<OwlEmotion>(find.byType(OwlEmotion)).mood, OwlMood.wink);
    await tester.pumpWidget(fixture(OwlLoading(
        size: 64, state: OwlLoadingState.error, onRetry: () => retries++)));
    await tester.pumpAndSettle();
    expect(tester.widget<OwlEmotion>(find.byType(OwlEmotion)).mood,
        OwlMood.patient);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    await tester
        .pumpWidget(fixture(const OwlLoading(state: OwlLoadingState.success)));
    await tester.pumpAndSettle();
    expect(
        tester.widget<OwlEmotion>(find.byType(OwlEmotion)).mood, OwlMood.happy);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(fixture(const OwlLoading(), ticking: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'route frames reuse their page child and respect reduced motion and RTL',
      (tester) async {
    final controller =
        AnimationController(vsync: tester, duration: AppMotion.enter);
    addTearDown(controller.dispose);
    var builds = 0;
    final page = Builder(builder: (_) {
      builds++;
      return const Text('Page');
    });
    await tester.pumpWidget(fixture(AppRouteTransition(
        animation: controller, style: AppTransitionStyle.detail, child: page)));
    controller.value = .5;
    await tester.pump();
    expect(builds, 1);
    expect(
        tester
            .widget<FractionalTranslation>(find.descendant(
                of: find.byType(AppRouteTransition),
                matching: find.byType(FractionalTranslation)))
            .translation
            .dx,
        greaterThan(0));
    await tester.pumpWidget(fixture(Directionality(
        textDirection: TextDirection.rtl,
        child: AppRouteTransition(
            animation: controller,
            style: AppTransitionStyle.detail,
            child: page))));
    expect(
        tester
            .widget<FractionalTranslation>(find.descendant(
                of: find.byType(AppRouteTransition),
                matching: find.byType(FractionalTranslation)))
            .translation
            .dx,
        lessThan(0));
    controller.value = 0;
    await tester.pumpWidget(fixture(
        AppRouteTransition(animation: controller, child: page),
        reduced: true));
    expect(find.text('Page'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AppRouteTransition),
            matching: find.byType(FractionalTranslation)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byType(AppRouteTransition),
            matching: find.byType(Opacity)),
        findsNothing);
  });

  testWidgets('emotion states render together without cropping or overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    await tester.pumpWidget(fixture(
        RepaintBoundary(
            key: capture,
            child: Container(
                width: 840,
                height: 520,
                color: const Color(0xFF0B0D17),
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('night owl',
                          style: TextStyle(fontSize: 28, color: Colors.white)),
                      const SizedBox(height: 28),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            const OwlLoading(size: 112, onDark: true),
                            const OwlLoading(
                                size: 112,
                                onDark: true,
                                state: OwlLoadingState.success),
                            OwlLoading(
                                size: 112,
                                onDark: true,
                                state: OwlLoadingState.error,
                                onRetry: () {}),
                          ]),
                      const SizedBox(height: 28),
                      SizedBox(
                          width: 248,
                          child: GradientButton(
                              label: 'Үргэлжлүүлэх', onPressed: () {})),
                    ]))),
        reduced: true));
    await tester.pumpAndSettle();
    await tester.runAsync(() => precacheImage(
        const ResizeImage(AssetImage('assets/images/owl_emotions.png'),
            width: 224),
        tester.element(find.byType(OwlEmotion).first)));
    await tester.pumpAndSettle();
    for (final raw in tester.widgetList<RawImage>(find.byType(RawImage))) {
      expect(raw.image, isNotNull,
          reason: 'Emotion asset must finish decoding.');
    }
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_MOTION_REVIEW')) {
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/night-owl-motion-review.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
