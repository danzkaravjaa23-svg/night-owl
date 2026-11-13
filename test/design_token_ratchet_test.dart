// DS-08 step 0: design token ratchet (design plan 2026-11-12, Phase 1).
//
// Reads the source text of lib/**/*.dart. Full-line `//` comments are
// skipped, so doc comments may still name the old APIs.
//
// * Hard zeros (all of lib): patterns the Phase 1 migration removed must not
//   come back.
// * Ceilings (lib/features only, so lib/core/theme is not counted): raw
//   literal counts may only go down. They were measured right after the
//   Phase 1 migration (2026-11-13). When a change removes literals, lower the
//   ceiling to the count this test prints.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ceilings for lib/features. Only ever lower them; new code uses AppSpacing,
/// AppRadii, AppColors and AppTextStyles instead of literals.
const _ceilings = (
  colorLiterals: 134,
  radiusLiterals: 196,
  gapLiterals: 642,
  fontSizeLiterals: 101,
  distinctRadii: 18,
  distinctGaps: 28,
);

// A number literal (12, 12.5 or .5) is `(\d+(?:\.\d+)?|\.\d+)`, group 1.

/// `Color(0x…)` written in a feature file instead of an AppColors token.
final _colorLiteral = RegExp(r'\bColor\(0x');

/// `BorderRadius.circular(12)` and `Radius.circular(12)`, each counted once.
final _radiusLiteral = RegExp(
    r'\b(?:BorderRadius|Radius)\.circular\(\s*(\d+(?:\.\d+)?|\.\d+)\s*\)');

/// A gap: `SizedBox(height: 12)` or `SizedBox(width: 8)` with nothing else.
final _gapLiteral = RegExp(
    r'\bSizedBox\(\s*(?:height|width)\s*:\s*(\d+(?:\.\d+)?|\.\d+)\s*,?\s*\)');

/// `fontSize: 14` (also `fontSize: 14 * scale`) instead of a text token.
final _fontSizeLiteral = RegExp(r'\bfontSize\s*:\s*(\d+(?:\.\d+)?|\.\d+)');

const _hardZeros = [
  _HardZero(
    'showModalBottomSheet',
    r'\bshowModalBottomSheet\s*[<(]',
    'open sheets with showAppSheet() (lib/core/widgets/app_sheet.dart)',
    allowed: ['lib/core/widgets/app_sheet.dart'],
  ),
  _HardZero(
    'GoogleFonts',
    r'\bGoogleFonts\.',
    'use AppTextStyles (the pubspec Inter family); only the theme and the '
        'story font picker load google_fonts',
    allowed: [
      'lib/core/theme/',
      'lib/features/feed/screens/create_story_screen.dart',
    ],
  ),
  _HardZero(
    'FontWeight.w900',
    r'\bFontWeight\.w900\b',
    'Inter ships up to w800; use FontWeight.w800 or an AppTextStyles token',
  ),
  _HardZero(
    'back glyph',
    r'\bIcons\.(?:arrow_back|keyboard_arrow_left|chevron_left)\w*',
    'use AppIcons.back through AppHeader or GlassIconButton',
    allowed: ['lib/core/theme/app_icons.dart'],
  ),
  _HardZero(
    'private header button class',
    r'class _\w*(?:TopIconBtn|GlassCircleButton|GlassIconButton|GlassBackBtn)\b',
    'use AppHeader actions or GlassIconButton (lib/core/widgets)',
  ),
];

void main() {
  final sources = _readLib();
  final features =
      sources.where((source) => source.path.startsWith('lib/features/'));

  test('the scan sees the whole lib tree', () {
    expect(sources.length, greaterThan(150));
    expect(features.length, greaterThan(100));
    expect(sources.map((source) => source.path),
        contains('lib/core/theme/app_icons.dart'));
  });

  test('the patterns catch what they are meant to catch', () {
    bool zero(String name, String code) => RegExp(
            _hardZeros.singleWhere((rule) => rule.name == name).pattern)
        .hasMatch(code);
    expect(zero('showModalBottomSheet', 'showModalBottomSheet<void>('), isTrue);
    expect(zero('showModalBottomSheet', 'showAppSheet<void>('), isFalse);
    expect(zero('GoogleFonts', 'GoogleFonts.inter(fontSize: 14)'), isTrue);
    expect(zero('FontWeight.w900', 'fontWeight: FontWeight.w900,'), isTrue);
    for (final glyph in [
      'arrow_back',
      'arrow_back_ios_new_rounded',
      'keyboard_arrow_left',
      'chevron_left_rounded',
    ]) {
      expect(zero('back glyph', 'Icon(Icons.$glyph)'), isTrue, reason: glyph);
    }
    expect(zero('back glyph', 'Icon(AppIcons.back)'), isFalse);
    expect(zero('private header button class', 'class _TopIconBtn extends'),
        isTrue);
    expect(
        zero('private header button class',
            'class _GlassIconButtonState extends'),
        isFalse);

    expect(_radiusLiteral.allMatches('BorderRadius.circular(12)').length, 1);
    expect(
        _radiusLiteral
            .allMatches('BorderRadius.all(Radius.circular(12.5))')
            .length,
        1);
    expect(_radiusLiteral.hasMatch('BorderRadius.circular(AppRadii.md)'),
        isFalse);
    expect(_gapLiteral.firstMatch('const SizedBox(height: 12)')?.group(1),
        '12');
    expect(_gapLiteral.hasMatch('SizedBox(\n  width: .5,\n)'), isTrue);
    expect(_gapLiteral.hasMatch('SizedBox(width: 40, height: 40)'), isFalse,
        reason: 'a fixed box is not a gap');
    expect(_gapLiteral.hasMatch('SizedBox(height: AppSpacing.x3)'), isFalse);
    expect(_fontSizeLiteral.hasMatch('fontSize: 14.5,'), isTrue);
    expect(_fontSizeLiteral.hasMatch('fontSize: size * 0.9'), isFalse);
    expect(_colorLiteral.hasMatch('const Color(0xFF7654D6)'), isTrue);
  });

  test('hard zeros stay at zero in lib', () {
    final problems = <String>[];
    for (final rule in _hardZeros) {
      final pattern = RegExp(rule.pattern);
      final hits = [
        for (final source in sources)
          if (!rule.allows(source.path))
            for (final line in source.lines)
              if (pattern.hasMatch(line.text))
                '    ${source.path}:${line.number}: ${line.text.trim()}',
      ];
      if (hits.isNotEmpty) {
        problems.add('  ${rule.name}: ${hits.length} found, must stay 0. '
            'Fix: ${rule.fix}.\n${hits.join('\n')}');
      }
    }
    if (problems.isNotEmpty) {
      fail('Design token ratchet (DS-08): a removed pattern came back.\n'
          '${problems.join('\n')}');
    }
  });

  test('literal counts in lib/features stay at or under their ceilings', () {
    final colors = _hits(features, _colorLiteral);
    final radii = _hits(features, _radiusLiteral);
    final gaps = _hits(features, _gapLiteral);
    final fontSizes = _hits(features, _fontSizeLiteral);
    final counters = [
      _Counter('Color(0x… literals', 'colorLiterals', colors.length,
          _ceilings.colorLiterals, () => _largestFiles(colors)),
      _Counter('BorderRadius/Radius.circular(<number>)', 'radiusLiterals',
          radii.length, _ceilings.radiusLiterals, () => _largestFiles(radii)),
      _Counter('SizedBox(height|width: <number>) gaps', 'gapLiterals',
          gaps.length, _ceilings.gapLiterals, () => _largestFiles(gaps)),
      _Counter('fontSize: <number>', 'fontSizeLiterals', fontSizes.length,
          _ceilings.fontSizeLiterals, () => _largestFiles(fontSizes)),
      _Counter('distinct radius values', 'distinctRadii', _values(radii).length,
          _ceilings.distinctRadii, () => _valueUse(radii)),
      _Counter('distinct SizedBox gap values', 'distinctGaps',
          _values(gaps).length, _ceilings.distinctGaps, () => _valueUse(gaps)),
    ];

    final grown = [
      for (final counter in counters)
        if (counter.count > counter.ceiling) counter,
    ];
    if (grown.isNotEmpty) {
      fail([
        'Design token ratchet (DS-08): literals in lib/features grew.',
        for (final counter in grown) ...[
          '  ${counter.label}: ${counter.count}, ceiling ${counter.ceiling} '
              '(+${counter.count - counter.ceiling})',
          '    ${counter.detail()}',
        ],
        'Use AppSpacing/AppRadii/AppColors/AppTextStyles tokens instead of '
            'new literals.',
        'If you removed literals, lower the ceiling in '
            'test/design_token_ratchet_test.dart (the ratchet only goes down).',
      ].join('\n'));
    }

    final summary = counters
        .map((counter) => '${counter.label} ${counter.count}/${counter.ceiling}')
        .join(' · ');
    debugPrint('Design token ratchet, lib/features (count/ceiling): $summary');
    final lower = [
      for (final counter in counters)
        if (counter.count < counter.ceiling)
          '${counter.field} ${counter.ceiling} → ${counter.count}',
    ];
    if (lower.isNotEmpty) {
      debugPrint('Literals went down. Lower these ceilings in '
          'test/design_token_ratchet_test.dart: ${lower.join(', ')}');
    }
  });
}

class _HardZero {
  const _HardZero(this.name, this.pattern, this.fix,
      {this.allowed = const []});

  final String name;
  final String pattern;
  final String fix;

  /// Files (or folders ending in `/`) where the pattern is the API itself.
  final List<String> allowed;

  bool allows(String path) => allowed.any((entry) =>
      entry.endsWith('/') ? path.startsWith(entry) : path == entry);
}

class _Counter {
  _Counter(this.label, this.field, this.count, this.ceiling, this.detail);

  final String label;

  /// Name of the field in `_ceilings`.
  final String field;
  final int count;
  final int ceiling;
  final String Function() detail;
}

typedef _Line = ({int number, String text});
typedef _Hit = ({String path, int line, double? value});

class _Source {
  _Source._(this.path, this.lines, this.code, this._starts);

  factory _Source.read(File file) {
    final lines = <_Line>[];
    final starts = <int>[];
    final code = StringBuffer();
    var number = 0;
    for (final text in const LineSplitter().convert(file.readAsStringSync())) {
      number++;
      if (text.trimLeft().startsWith('//')) continue;
      lines.add((number: number, text: text));
      starts.add(code.length);
      code
        ..write(text)
        ..write('\n');
    }
    return _Source._(
        file.path.replaceAll('\\', '/'), lines, code.toString(), starts);
  }

  /// Path relative to the package root, with forward slashes.
  final String path;

  /// Lines that are not full-line comments, with their 1-based numbers.
  final List<_Line> lines;

  /// [lines] joined by newlines, so a pattern may span lines.
  final String code;

  /// Offset in [code] where each of [lines] starts.
  final List<int> _starts;

  /// File line number of an offset in [code].
  int lineAt(int offset) {
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return lines[low].number;
  }
}

List<_Source> _readLib() => [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          _Source.read(entity),
    ]..sort((a, b) => a.path.compareTo(b.path));

List<_Hit> _hits(Iterable<_Source> sources, RegExp pattern) => [
      for (final source in sources)
        for (final match in pattern.allMatches(source.code))
          (
            path: source.path,
            line: source.lineAt(match.start),
            value: match.groupCount == 0 ? null : double.parse(match.group(1)!),
          ),
    ];

Set<double> _values(List<_Hit> hits) => {for (final hit in hits) hit.value!};

String _format(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// The files with the most hits, to show where to look first.
String _largestFiles(List<_Hit> hits) {
  final perFile = <String, int>{};
  for (final hit in hits) {
    perFile[hit.path] = (perFile[hit.path] ?? 0) + 1;
  }
  final ranked = perFile.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = ranked.take(6).map((entry) => '${entry.key} (${entry.value})');
  return 'most in: ${top.join(', ')}';
}

/// Every value with its use count. Rare values also say where they are, as a
/// new value usually shows up once.
String _valueUse(List<_Hit> hits) {
  final byValue = <double, List<_Hit>>{};
  for (final hit in hits) {
    byValue.putIfAbsent(hit.value!, () => []).add(hit);
  }
  final values = byValue.keys.toList()..sort();
  final parts = <String>[];
  for (final value in values) {
    final uses = byValue[value]!;
    final where = uses.length > 2
        ? ''
        : ' at ${uses.map((hit) => '${hit.path}:${hit.line}').join(', ')}';
    parts.add('${_format(value)} ×${uses.length}$where');
  }
  return 'values: ${parts.join('; ')}';
}
