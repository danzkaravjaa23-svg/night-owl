import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/features/map/widgets/venue_story_badge.dart';
import 'package:night_owl_ub/models/venue_story_activity.dart';

Widget _legend({
  bool reduced = false,
  bool accessible = false,
  bool ticking = true,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          accessibleNavigation: accessible,
        ),
        child: TickerMode(
          enabled: ticking,
          child: const Scaffold(body: VenueStoryLegend()),
        ),
      ),
    );

Animation<double> _sharedPhase(WidgetTester tester) {
  final badges =
      tester.widgetList<VenueStoryBadge>(find.byType(VenueStoryBadge));
  expect(badges.map((badge) => badge.level), VenueStoryLevel.values);
  final phase = badges.first.phase;
  expect(badges.every((badge) => identical(badge.phase, phase)), isTrue,
      reason: 'All four emotions should share one paint clock.');
  return phase;
}

Future<Uint8List> _paintedPixels(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

bool _samePixels(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  testWidgets('legend emotions keep moving beyond their first six-second cycle',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_legend());
    final phase = _sharedPhase(tester);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final before = phase.value;
    expect(before, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 6250));
    expect(phase.value, inInclusiveRange(0.0, 1.0));
    expect((phase.value - before).abs(), greaterThan(.01),
        reason: 'The preview must continue animating after a complete cycle.');
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(identical(_sharedPhase(tester), phase), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final accessible in [false, true]) {
    testWidgets(
        'legend stops and restarts for ${accessible ? 'accessible navigation' : 'reduced animation'}',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_legend());
      final phase = _sharedPhase(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(phase.value, greaterThan(0));
      await tester
          .pumpWidget(_legend(reduced: !accessible, accessible: accessible));
      await tester.pumpAndSettle();
      expect(phase.value, 0);
      await tester.pump(const Duration(seconds: 8));
      expect(phase.value, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(_legend());
      expect(identical(_sharedPhase(tester), phase), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(phase.value, greaterThan(0));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'offstage ticker mode freezes the legend until it becomes visible',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_legend());
    final phase = _sharedPhase(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(phase.value, greaterThan(0));
    await tester.pumpWidget(_legend(ticking: false));
    await tester.pumpAndSettle();
    expect(phase.value, 0);
    await tester.pump(const Duration(seconds: 8));
    expect(phase.value, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_legend());
    expect(identical(_sharedPhase(tester), phase), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(phase.value, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'background legend resets its clock and resumes in the foreground',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(_legend());
    final phase = _sharedPhase(tester);
    try {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(phase.value, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 8));
      expect(phase.value, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(phase.value, greaterThan(0));
      expect(tester.binding.hasScheduledFrame, isTrue);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('all four emotions fit their pin and preview boxes at any phase',
      (tester) async {
    final phase = AnimationController(vsync: tester);
    try {
      for (final size in [28.0, 36.0, 96.0]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final level in VenueStoryLevel.values)
                    VenueStoryBadge(level: level, phase: phase, size: size),
                ],
              ),
            ),
          ),
        ));
        for (final value in [0.0, .13, .37, .64, .99, 1.0]) {
          phase.value = value;
          await tester.pump();
          for (final badge in find.byType(VenueStoryBadge).evaluate()) {
            final box = badge.renderObject! as RenderBox;
            expect(box.size, Size.square(size));
          }
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
    } finally {
      phase.dispose();
    }
  });

  testWidgets('pin emotions visibly move, loop seamlessly, and paint in bounds',
      (tester) async {
    final phase = AnimationController(vsync: tester);
    try {
      for (final size in [32, 48]) {
        final side = size + 16;
        for (final level in VenueStoryLevel.values) {
          final capture = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: capture,
                  child: SizedBox.square(
                    dimension: side.toDouble(),
                    child: Center(
                      child: VenueStoryBadge(
                          level: level, phase: phase, size: size.toDouble()),
                    ),
                  ),
                ),
              ),
            ),
          ));
          final samples = <Uint8List>[];
          // A quarter-cycle can be the same pose in a two-bounce rhythm.
          for (final value in [0.0, .125, 1.0]) {
            phase.value = value;
            await tester.pump();
            final pixels = await tester.runAsync(() => _paintedPixels(capture));
            samples.add(pixels!);
            var outsidePixels = 0;
            for (var y = 0; y < side; y++) {
              for (var x = 0; x < side; x++) {
                if (x >= 8 && x < size + 8 && y >= 8 && y < size + 8) {
                  continue;
                }
                if (pixels[(y * side + x) * 4 + 3] != 0) outsidePixels++;
              }
            }
            expect(outsidePixels, 0,
                reason: '${level.name} at $size px must not paint over '
                    'nearby map controls or neighbouring pins (phase $value).');
          }
          expect(_samePixels(samples.first, samples[1]), isFalse,
              reason: '${level.name} should visibly move during its loop.');
          expect(_samePixels(samples.first, samples.last), isTrue,
              reason: '${level.name} should return to its first frame '
                  'without a jump at the loop seam.');
        }
      }
      await tester.pumpWidget(const SizedBox());
    } finally {
      phase.dispose();
    }
    expect(tester.takeException(), isNull);
  });
}
