import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

class _ForbiddenFontCache extends PathProviderPlatform {
  int lookups = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    lookups++;
    throw StateError('A first launch must not need a downloaded font cache.');
  }
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
    final styles = [
      AppTextStyles.displayLg,
      AppTextStyles.displayMd,
      AppTextStyles.displaySm,
      AppTextStyles.h1,
      AppTextStyles.h2,
      AppTextStyles.h3,
      AppTextStyles.bodyLg,
      AppTextStyles.bodyMd,
      AppTextStyles.bodySm,
      AppTextStyles.bodyXs,
      AppTextStyles.labelLg,
      AppTextStyles.labelMd,
      AppTextStyles.labelSm,
      AppTextStyles.sectionLabel,
      AppTextStyles.mono,
      AppTextStyles.monoSm,
      AppTextStyles.btn,
      AppTextStyles.btnSm,
      GoogleFonts.manrope(fontWeight: FontWeight.w800),
      GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
      GoogleFonts.pacifico(),
      GoogleFonts.bebasNeue(),
    ];
    await GoogleFonts.pendingFonts(styles).timeout(const Duration(seconds: 10));

    expect(themes.map((theme) => theme.brightness),
        [Brightness.dark, Brightness.light]);
    expect(styles.every((style) => style.fontFamily != null), isTrue);
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    expect(requests, 0);
    expect(cache.lookups, 0);
  });

  test('app and story direct font calls require only bundled variants',
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
        // Theme factories are exercised above. Waiting for already requested
        // fonts (e.g. before baking a story overlay) requests no new variant.
        if (const {'interTextTheme', 'pendingFonts'}.contains(method)) continue;
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
    expect(requested, unorderedEquals(bundled));
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
