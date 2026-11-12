import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';

/// WCAG 2.x relative luminance of an opaque colour.
double _luminance(Color c) {
  double channel(double v) => v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio (1..21) between two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => AppColors.isDarkMode = true);

  test('contrast helper matches known WCAG values', () {
    expect(_contrast(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(_contrast(Colors.white, Colors.white), closeTo(1, 0.001));
  });

  for (final dark in [true, false]) {
    final mode = dark ? 'Night' : 'Day';

    test('$mode: accentText reaches 4.5:1 on every app surface', () {
      AppColors.isDarkMode = dark;
      final surfaces = {
        'bgBase': AppColors.bgBase,
        'bgSurface': AppColors.bgSurface,
        'bgElevated': AppColors.bgElevated,
      };
      for (final entry in surfaces.entries) {
        final ratio = _contrast(AppColors.accentText, entry.value);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: 'accentText on ${entry.key} is '
                '${ratio.toStringAsFixed(2)}:1');
      }
    });

    test('$mode: like and saved reach 3:1 on card and surface', () {
      AppColors.isDarkMode = dark;
      final surfaces = {
        'bgBase': AppColors.bgBase,
        'bgSurface': AppColors.bgSurface,
        'bgElevated': AppColors.bgElevated,
      };
      for (final entry in surfaces.entries) {
        final like = _contrast(AppColors.like, entry.value);
        final saved = _contrast(AppColors.saved, entry.value);
        expect(like, greaterThanOrEqualTo(3.0),
            reason: 'like on ${entry.key} is ${like.toStringAsFixed(2)}:1');
        expect(saved, greaterThanOrEqualTo(3.0),
            reason: 'saved on ${entry.key} is ${saved.toStringAsFixed(2)}:1');
      }
    });
  }

  test('Night: accent tokens resolve to the bright lavender', () {
    AppColors.isDarkMode = true;
    expect(AppColors.accentText, const Color(0xFFB6A4FF));
    expect(AppColors.like, const Color(0xFFB6A4FF));
    expect(AppColors.saved, const Color(0xFFB6A4FF));
  });

  test('Day: accentText is #6550AD and like/saved keep their old values', () {
    AppColors.isDarkMode = false;
    expect(AppColors.accentText, const Color(0xFF6550AD));
    expect(AppColors.like, const Color(0xFF6745C1));
    expect(AppColors.saved, const Color(0xFF7654D6));
  });

  test('Night: liked heart is brighter than the old #6745C1', () {
    AppColors.isDarkMode = true;
    const oldLike = Color(0xFF6745C1);
    expect(_luminance(AppColors.like), greaterThan(_luminance(oldLike)));
    expect(_contrast(AppColors.like, AppColors.bgElevated),
        greaterThan(_contrast(oldLike, AppColors.bgElevated)));
  });
}
