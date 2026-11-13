import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// The package exposes these cache/client hooks specifically for testing.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_loader;
import 'package:http/testing.dart';
import 'package:night_owl_ub/core/theme/app_fonts.dart';
import 'package:night_owl_ub/core/theme/app_text_styles.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
// Exercise the transitive font-cache interface without a real device cache.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Read pubspec.yaml with the same parser the Flutter tool uses.
// ignore: depend_on_referenced_packages
import 'package:yaml/yaml.dart';

class _ForbiddenFontCache extends PathProviderPlatform {
  int lookups = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    lookups++;
    throw StateError('A first launch must not need a downloaded font cache.');
  }
}

/// Every font file that pubspec.yaml registers under `flutter > fonts`.
List<({String family, String asset, int weight, String style})>
    _pubspecFonts() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
  final flutter = pubspec['flutter'] as Map;
  return [
    for (final family in (flutter['fonts'] as List? ?? const []).cast<Map>())
      for (final font in (family['fonts'] as List).cast<Map>())
        (
          family: family['family'] as String,
          asset: font['asset'] as String,
          weight: font['weight'] as int? ?? 400,
          style: font['style'] as String? ?? 'normal',
        ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every packaged font and license matches its pinned source bytes',
      () async {
    final provenance = jsonDecode(
      await rootBundle.loadString('assets/fonts/manifest.json'),
    ) as Map<String, dynamic>;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = [
      ...provenance['fonts'] as List,
      ...provenance['licenses'] as List,
    ];
    expect((provenance['fonts'] as List), hasLength(10));
    expect((provenance['licenses'] as List), hasLength(6));
    // Detect a dependency update that changes the requested files, instead of
    // silently retaining a differently-versioned asset under the same name.
    final packageConfig = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final package = (packageConfig['packages'] as List)
        .singleWhere((entry) => entry['name'] == 'google_fonts');
    final configUri = File('.dart_tool/package_config.json').absolute.uri;
    final packageRoot =
        Directory.fromUri(configUri.resolve(package['rootUri'] as String)).uri;
    final packagePubspec =
        File.fromUri(packageRoot.resolve('pubspec.yaml')).readAsStringSync();
    expect(packagePubspec,
        contains('version: ${provenance['google_fonts_version']}'));
    for (final font in provenance['fonts'] as List) {
      final family = font['family'] as String;
      final source = File.fromUri(packageRoot.resolve(
        'lib/src/google_fonts_parts/part_${family[0].toLowerCase()}.g.dart',
      )).readAsStringSync();
      expect(
          source, contains("'${font['sha256']}',\n        ${font['bytes']},"));
    }
    for (final file in files) {
      final path = 'assets/fonts/${file['file']}';
      expect(manifest.listAssets(), contains(path));
      final data = await rootBundle.load(path);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(bytes.length, file['bytes'], reason: path);
      expect(sha256.convert(bytes).toString(), file['sha256'], reason: path);
    }
  });

  test('pubspec registers the five bundled Inter files as one font family',
      () async {
    final provenance = jsonDecode(
      await rootBundle.loadString('assets/fonts/manifest.json'),
    ) as Map<String, dynamic>;
    final bundledInter = {
      for (final font in provenance['fonts'] as List)
        if (font['family'] == AppTextStyles.fontFamily)
          'assets/fonts/${font['file']}': '${font['weight']}:${font['style']}',
    };
    expect(bundledInter, hasLength(5));

    final declared = _pubspecFonts();
    expect(declared.map((font) => font.asset).toSet(), hasLength(declared.length),
        reason: 'A font file must be declared once');
    final declaredInter = {
      for (final font in declared)
        if (font.family == AppTextStyles.fontFamily)
          font.asset: '${font.weight}:${font.style}',
    };
    expect(declaredInter, bundledInter);

    // The engine registers families from the tool's FontManifest.json on
    // launch; it must carry the same Inter files and weights.
    final fontManifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final built = fontManifest
        .cast<Map<String, dynamic>>()
        .singleWhere((family) => family['family'] == AppTextStyles.fontFamily);
    expect({
      for (final font in (built['fonts'] as List).cast<Map<String, dynamic>>())
        font['asset'] as String:
            '${font['weight'] ?? 400}:${font['style'] ?? 'normal'}',
    }, bundledInter);
  });

  test('each Inter weight renders its own bundled file, never a fake bold',
      () async {
    final inter = _pubspecFonts()
        .where((font) => font.family == AppTextStyles.fontFamily)
        .toList()
      ..sort((a, b) => a.weight.compareTo(b.weight));
    expect(inter.map((font) => font.weight), [400, 500, 600, 700, 800]);
    // A single-file probe family per weight gives the reference metrics.
    for (final font in inter) {
      final probe = FontLoader('InterProbe${font.weight}')
        ..addFont(rootBundle.load(font.asset));
      await probe.load();
    }
    double width(String family, int weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'Шөнийн шар шувуу · Night Owl 2026',
          style: TextStyle(
            fontFamily: family,
            fontSize: 40,
            fontWeight: FontWeight(weight),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    final widths = <double>[];
    for (final font in inter) {
      // flutter_test_config registers the app's Inter family the way the
      // engine does on launch. Each weight must select its own file instead
      // of emboldening the Regular outlines.
      final real = width(AppTextStyles.fontFamily, font.weight);
      expect(real, closeTo(width('InterProbe${font.weight}', font.weight), 0.01),
          reason: 'Inter w${font.weight} must render ${font.asset}');
      widths.add(real);
    }
    // Heavier Inter files are wider, so every weight is a distinct face.
    for (var i = 1; i < widths.length; i++) {
      expect(widths[i], greaterThan(widths[i - 1]),
          reason: 'w${inter[i].weight} vs w${inter[i - 1].weight}');
    }
  });

  test(
      'fresh app theme and every story font load with no network or disk cache',
      () async {
    final oldCache = PathProviderPlatform.instance;
    final oldClient = font_loader.httpClient;
    final oldFetching = GoogleFonts.config.allowRuntimeFetching;
    final cache = _ForbiddenFontCache();
    var requests = 0;
    final offlineClient = MockClient((request) async {
      requests++;
      throw StateError('Offline: ${request.url}');
    });
    addTearDown(() {
      PathProviderPlatform.instance = oldCache;
      font_loader.httpClient = oldClient;
      GoogleFonts.config.allowRuntimeFetching = oldFetching;
      offlineClient.close();
    });
    PathProviderPlatform.instance = cache;
    font_loader.httpClient = offlineClient;
    font_loader.clearCache();
    font_loader.assetManifest = null;
    AppFonts.configure();

    // Exercise the actual theme (including inherited Material weights), all
    // app tokens, and the four existing story selector choices.
    final themes = [AppTheme.dark, AppTheme.light];
    final interTokens = [
      AppTextStyles.displayLg,
      AppTextStyles.displayMd,
      AppTextStyles.displaySm,
      AppTextStyles.pageTitle,
      AppTextStyles.title,
      AppTextStyles.h1,
      AppTextStyles.h2,
      AppTextStyles.h3,
      AppTextStyles.bodyLg,
      AppTextStyles.bodyMd,
      AppTextStyles.bodySm,
      AppTextStyles.bodyXs,
      AppTextStyles.caption,
      AppTextStyles.labelLg,
      AppTextStyles.labelMd,
      AppTextStyles.labelSm,
      AppTextStyles.sectionLabel,
      AppTextStyles.btn,
      AppTextStyles.btnSm,
    ];
    final styles = [
      ...interTokens,
      AppTextStyles.mono,
      AppTextStyles.monoSm,
      GoogleFonts.manrope(fontWeight: FontWeight.w800),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
      GoogleFonts.pacifico(),
      GoogleFonts.bebasNeue(),
    ];
    await GoogleFonts.pendingFonts(styles).timeout(const Duration(seconds: 10));

    expect(themes.map((theme) => theme.brightness),
        [Brightness.dark, Brightness.light]);
    expect(styles.every((style) => style.fontFamily != null), isTrue);
    // App text uses the pubspec Inter family, never a per-weight google_fonts
    // family, so a weight added on an inherited style picks a real file.
    for (final style in interTokens) {
      expect(style.fontFamily, AppTextStyles.fontFamily);
    }
    for (final theme in themes) {
      final text = theme.textTheme;
      for (final style in [
        text.displayLarge,
        text.displayMedium,
        text.displaySmall,
        text.headlineLarge,
        text.headlineMedium,
        text.headlineSmall,
        text.titleLarge,
        text.titleMedium,
        text.titleSmall,
        text.bodyLarge,
        text.bodyMedium,
        text.bodySmall,
        text.labelLarge,
        text.labelMedium,
        text.labelSmall,
      ]) {
        expect(style?.fontFamily, AppTextStyles.fontFamily);
      }
    }
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    expect(requests, 0);
    expect(cache.lookups, 0);
  });

  test('google_fonts requests and pubspec families cover only bundled variants',
      () async {
    final provenance = jsonDecode(
      await rootBundle.loadString('assets/fonts/manifest.json'),
    ) as Map<String, dynamic>;
    final bundled = {
      for (final file in provenance['fonts'] as List)
        '${file['family']}:${file['weight']}:${file['style']}',
    };
    const families = {
      'inter': 'Inter',
      'jetBrainsMono': 'JetBrainsMono',
      'manrope': 'Manrope',
      'playfairDisplay': 'PlayfairDisplay',
      'pacifico': 'Pacifico',
      'bebasNeue': 'BebasNeue',
    };
    final requested = <String>{};
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final call
          in RegExp(r'GoogleFonts\.(\w+)\(([^;]*?)\)').allMatches(source)) {
        final method = call.group(1)!;
        // Waiting for already requested fonts (e.g. before baking a story
        // overlay) requests no new variant. Text theme factories are not
        // allowed: they would bring back per-weight families.
        if (method == 'pendingFonts') continue;
        expect(families, contains(method), reason: file.path);
        final args = call.group(2)!;
        final weightMatch =
            RegExp(r'fontWeight:\s*FontWeight\.w(\d+)').firstMatch(args);
        if (args.contains('fontWeight:')) {
          expect(weightMatch, isNotNull,
              reason: 'Add coverage for dynamic font weights in ${file.path}');
        }
        final weight = weightMatch?.group(1) ?? '400';
        final style = args.contains('FontStyle.italic') ? 'italic' : 'normal';
        requested.add('${families[method]}:$weight:$style');
      }
    }
    final declared = {
      for (final font in _pubspecFonts())
        '${font.family}:${font.weight}:${font.style}',
    };
    expect(declared, isNotEmpty);
    expect(requested.union(declared), unorderedEquals(bundled));
  });

  test('all six bundled OFLs are registered once for the app license screen',
      () async {
    AppFonts.configure();
    AppFonts.configure();
    const families = {
      'Inter',
      'JetBrainsMono',
      'Manrope',
      'PlayfairDisplay',
      'Pacifico',
      'BebasNeue',
    };
    final entries = await LicenseRegistry.licenses
        .where((entry) => entry.packages.any(families.contains))
        .toList();
    expect(entries, hasLength(6));
    expect(
        entries.expand((entry) => entry.packages), unorderedEquals(families));
    for (final entry in entries) {
      final text =
          entry.paragraphs.map((paragraph) => paragraph.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(text.toLowerCase(), contains('copyright'));
    }
  });
}
