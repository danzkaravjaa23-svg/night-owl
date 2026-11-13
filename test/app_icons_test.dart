import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/theme/app_icons.dart';

/// Quoted keys inside the first `{ … }` block that follows [opening] in the
/// lib file at [path]: the arms of a `switch` or the keys of a map literal.
Set<String> _keysIn(String path, RegExp opening, RegExp key) {
  final source = File(path).readAsStringSync();
  final start = opening.firstMatch(source);
  if (start == null) {
    throw StateError('${opening.pattern} not found in $path; update this '
        'test to read the venue type keys from their new place.');
  }
  final end = source.indexOf('}', start.end);
  return {
    for (final match in key.allMatches(source.substring(start.end, end)))
      match.group(1)!,
  };
}

final _switchArm = RegExp(r"'(\w+)'\s*=>");
final _mapKey = RegExp(r"'(\w+)'\s*:");

/// Every venue type key lib uses: the model's type labels, the map's
/// category filter (including its `bars` group) and the venue editor.
Map<String, Set<String>> _venueTypeKeys() => {
      'Venue.typeLabel': _keysIn('lib/models/venue.dart',
          RegExp(r'typeLabel\s*=>\s*switch\s*\(\s*type\s*\)\s*\{'), _switchArm),
      'map categories': _keysIn('lib/features/map/screens/map_screen.dart',
          RegExp(r'_categories\s*=\s*\{'), _mapKey),
      'venue editor types': _keysIn(
          'lib/features/profile/screens/venue_edit_screen.dart',
          RegExp(r'_kVenueTypes\s*=\s*<String,\s*String>\s*\{'),
          _mapKey),
    };

void main() {
  group('AppIcons.venueType', () {
    test('every venue type key in lib has its own glyph', () {
      final keys = _venueTypeKeys();
      // The parsing must find real keys, or this test would pass vacuously.
      for (final entry in keys.entries) {
        expect(entry.value.length, greaterThanOrEqualTo(6), reason: entry.key);
      }
      final all = {for (final set in keys.values) ...set};
      expect(
          all,
          containsAll(const [
            'bar',
            'bars',
            'pub',
            'lounge',
            'rooftop',
            'nightclub',
            'karaoke',
            'jazz',
            'restaurant',
            'cafe',
          ]));
      final fallback = AppIcons.venueType(null);
      for (final entry in keys.entries) {
        for (final key in entry.value) {
          expect(AppIcons.venueType(key), isNot(fallback),
              reason: "'$key' (${entry.key}) falls back to the generic pin; "
                  'add it to AppIcons.venueType');
        }
      }
    });

    test('unknown, empty and missing types get the filled venue pin', () {
      for (final type in [null, '', '   ', 'venue', 'hookah', 'bar & grill']) {
        expect(AppIcons.venueType(type), AppIcons.venueActive,
            reason: '$type');
      }
    });

    test('keys are matched without case or surrounding spaces', () {
      expect(AppIcons.venueType(' Nightclub '), AppIcons.venueType('nightclub'));
      expect(AppIcons.venueType('KARAOKE'), AppIcons.venueType('karaoke'));
      // The map's "Бар" filter groups bar, pub, lounge and rooftop.
      expect(AppIcons.venueType('bars'), AppIcons.venueType('bar'));
    });
  });

  test('share uses the iOS glyph on Apple platforms, Android elsewhere', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    try {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        final apple = platform == TargetPlatform.iOS ||
            platform == TargetPlatform.macOS;
        expect(AppIcons.share,
            apple ? Icons.ios_share_rounded : Icons.share_rounded,
            reason: '$platform');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
