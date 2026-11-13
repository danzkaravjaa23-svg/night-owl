import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';

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

void _expectContrast(String label, Color fg, Color bg, double min) {
  final ratio = _contrast(fg, bg);
  expect(ratio, greaterThanOrEqualTo(min),
      reason: '$label is ${ratio.toStringAsFixed(2)}:1');
}

/// The opaque app surfaces of the current [AppColors.isDarkMode].
Map<String, Color> _surfaces() => {
      'bgBase': AppColors.bgBase,
      'bgSurface': AppColors.bgSurface,
      'bgElevated': AppColors.bgElevated,
    };

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

    test('$mode: danger and warning text reach 4.5:1 on every app surface',
        () {
      AppColors.isDarkMode = dark;
      for (final entry in _surfaces().entries) {
        _expectContrast(
            'danger on ${entry.key}', AppColors.danger, entry.value, 4.5);
        _expectContrast(
            'warning on ${entry.key}', AppColors.warning, entry.value, 4.5);
      }
    });

    test('$mode: rating stars reach 3:1 on every app surface', () {
      AppColors.isDarkMode = dark;
      for (final entry in _surfaces().entries) {
        _expectContrast(
            'rating on ${entry.key}', AppColors.rating, entry.value, 3.0);
      }
    });

    test('$mode: theme pairs every fill and surface with legible content',
        () {
      final theme = dark ? AppTheme.dark : AppTheme.light;
      final scheme = theme.colorScheme;
      final base = theme.scaffoldBackgroundColor;
      final elevated =
          dark ? AppColors.bgElevatedDark : AppColors.bgElevatedLight;
      const none = <WidgetState>{};
      const selected = {WidgetState.selected};
      Color colorIn(Color? color, Set<WidgetState> states) =>
          WidgetStateProperty.resolveAs<Color?>(color, states)!;
      Color labelIn(Set<WidgetState> states) =>
          WidgetStateProperty.resolveAs<TextStyle?>(
                  theme.inputDecorationTheme.floatingLabelStyle, states)!
              .color!;
      final chip = theme.chipTheme;
      final tile = theme.listTileTheme;
      final filled = theme.filledButtonTheme.style!;
      final datePicker = theme.datePickerTheme;
      final input = theme.inputDecorationTheme;
      final tooltip = theme.tooltipTheme.decoration! as BoxDecoration;
      final pairs = <String, (Color, Color)>{
        'onPrimary/primary': (scheme.onPrimary, scheme.primary),
        'onPrimaryContainer/primaryContainer':
            (scheme.onPrimaryContainer, scheme.primaryContainer),
        'onSecondary/secondary': (scheme.onSecondary, scheme.secondary),
        'onSecondaryContainer/secondaryContainer':
            (scheme.onSecondaryContainer, scheme.secondaryContainer),
        'onTertiary/tertiary': (scheme.onTertiary, scheme.tertiary),
        'onError/error': (scheme.onError, scheme.error),
        'onErrorContainer/errorContainer':
            (scheme.onErrorContainer, scheme.errorContainer),
        'onInverseSurface/inverseSurface':
            (scheme.onInverseSurface, scheme.inverseSurface),
        'filled button label': (
          filled.foregroundColor!.resolve(none)!,
          filled.backgroundColor!.resolve(none)!,
        ),
        'text button on page': (
          theme.textButtonTheme.style!.foregroundColor!.resolve(none)!,
          base,
        ),
        'selected chip label (white on accentStart)':
            (colorIn(chip.labelStyle!.color, selected), chip.selectedColor!),
        'chip label': (colorIn(chip.labelStyle!.color, none), chip.backgroundColor!),
        'selected list tile': (
          tile.selectedColor!,
          Color.alphaBlend(tile.selectedTileColor!, elevated),
        ),
        'list tile subtitle': (tile.subtitleTextStyle!.color!, elevated),
        'tab label': (theme.tabBarTheme.labelColor!, base),
        'unselected tab label': (theme.tabBarTheme.unselectedLabelColor!, base),
        'selected date': (
          datePicker.dayForegroundColor!.resolve(selected)!,
          datePicker.dayBackgroundColor!.resolve(selected)!,
        ),
        'today': (
          datePicker.todayForegroundColor!.resolve(none)!,
          datePicker.backgroundColor!,
        ),
        'focused field label':
            (labelIn({WidgetState.focused}), input.fillColor!),
        'field label with error':
            (labelIn({WidgetState.error}), input.fillColor!),
        'field error text': (input.errorStyle!.color!, input.fillColor!),
        'badge': (theme.badgeTheme.textColor!, theme.badgeTheme.backgroundColor!),
        'tooltip': (theme.tooltipTheme.textStyle!.color!, tooltip.color!),
      };
      for (final entry in pairs.entries) {
        _expectContrast(entry.key, entry.value.$1, entry.value.$2, 4.5);
      }
      final surfaces = {
        'surface': scheme.surface,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
      };
      for (final entry in surfaces.entries) {
        _expectContrast(
            'onSurface on ${entry.key}', scheme.onSurface, entry.value, 4.5);
        _expectContrast('onSurfaceVariant on ${entry.key}',
            scheme.onSurfaceVariant, entry.value, 4.5);
        // primary is the text/icon accent, so unthemed Material text stays AA.
        _expectContrast(
            'primary on ${entry.key}', scheme.primary, entry.value, 4.5);
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

  test('Night: status tokens keep the bright values', () {
    AppColors.isDarkMode = true;
    expect(AppColors.danger, const Color(0xFFFF4566));
    expect(AppColors.danger, AppColors.error);
    expect(AppColors.warning, const Color(0xFFFFB020));
    expect(AppColors.rating, const Color(0xFFFFB020));
  });

  test('Day: status tokens switch to their AA values', () {
    AppColors.isDarkMode = false;
    expect(AppColors.danger, const Color(0xFFC81E3A));
    expect(AppColors.warning, const Color(0xFF8A5A00));
    expect(AppColors.rating, const Color(0xFFB7791F));
  });

  test('white text reaches 4.5:1 on the danger and brand fills', () {
    _expectContrast(
        'white on dangerFill', Colors.white, AppColors.dangerFill, 4.5);
    _expectContrast(
        'white on accentStart', Colors.white, AppColors.accentStart, 4.5);
  });

  test('liked heart and saved mark on always-dark media reach 3:1 in both '
      'themes', () {
    for (final dark in [true, false]) {
      AppColors.isDarkMode = dark;
      expect(AppColors.likeOnMedia, const Color(0xFFB6A4FF));
      _expectContrast('likeOnMedia on bgBaseDark', AppColors.likeOnMedia,
          AppColors.bgBaseDark, 3.0);
      expect(AppColors.savedOnMedia, const Color(0xFFB6A4FF));
      _expectContrast('savedOnMedia on bgBaseDark', AppColors.savedOnMedia,
          AppColors.bgBaseDark, 3.0);
    }
  });

  test('accentGradient is the shared primary gradient', () {
    expect(AppColors.accentGradient, AppGradients.primary);
    expect(AppGradients.primary.colors, const [
      Color(0xFF8661DC),
      Color(0xFF7654D6),
      Color(0xFF5D3AAB),
    ]);
  });

  test('AppTheme derives its colours from its own brightness only', () {
    for (final build in [() => AppTheme.dark, () => AppTheme.light]) {
      AppColors.isDarkMode = true;
      final whileNight = build();
      AppColors.isDarkMode = false;
      final whileDay = build();
      expect(whileDay.colorScheme, whileNight.colorScheme);
      expect(whileDay.textTheme, whileNight.textTheme);
      expect(whileDay.listTileTheme, whileNight.listTileTheme);
      expect(whileDay.inputDecorationTheme.errorStyle,
          whileNight.inputDecorationTheme.errorStyle);
    }
  });
}
