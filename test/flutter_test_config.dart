import 'dart:async';

import 'package:night_owl_ub/core/widgets/eclipse_theme_toggle.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  EclipseThemeToggle.ambientFlow = false;
  await testMain();
}
