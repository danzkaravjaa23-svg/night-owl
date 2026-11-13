import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/theme/app_text_styles.dart';
import 'package:night_owl_ub/core/widgets/eclipse_theme_toggle.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadBundledInter();
  EclipseThemeToggle.ambientFlow = false;
  await testMain();
}

/// flutter_test нь pubspec.yaml-ийн `fonts:`-ийг өөрөө ачаалдаггүй тул
/// бүртгэлгүй family FlutterTest фонт руу унадаг. Апп эхлэхэд engine-ийн
/// уншдаг FontManifest.json-оос Inter family-ийн 5 файлыг нэг удаа бүртгэснээр
/// widget тест ба visual capture жинхэнэ жинтэй Inter-ээр хэмжиж, зурна.
Future<void> _loadBundledInter() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  final inter = manifest.cast<Map<String, dynamic>>().firstWhere(
        (family) => family['family'] == AppTextStyles.fontFamily,
        orElse: () => throw StateError(
            'pubspec.yaml must declare the ${AppTextStyles.fontFamily} font '
            'family under flutter > fonts.'),
      );
  final loader = FontLoader(AppTextStyles.fontFamily);
  for (final font in (inter['fonts'] as List).cast<Map<String, dynamic>>()) {
    loader.addFont(rootBundle.load(font['asset'] as String));
  }
  await loader.load();
}
