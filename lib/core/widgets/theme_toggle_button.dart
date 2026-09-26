import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme_provider.dart';
import 'eclipse_theme_toggle.dart';
import 'theme_reveal.dart';

/// Апп-ын горимтой холбогдсон хиртэлтийн toggle.
/// Дарахад шинэ горим toggle-ийн төвөөс тойрог болон тэлнэ ([ThemeReveal]).
class ThemeToggleButton extends ConsumerWidget {
  final double width;
  final double height;

  const ThemeToggleButton({super.key, this.width = 60, this.height = 30});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return EclipseThemeToggle(
      isDark: isDark,
      width: width,
      height: height,
      onChanged: (dark) {
        final notifier = ref.read(themeModeProvider.notifier);
        Future<void> apply() =>
            notifier.setMode(dark ? ThemeMode.dark : ThemeMode.light);

        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null && box.hasSize
            ? box.localToGlobal(box.size.center(Offset.zero))
            : null;
        final reveal = ThemeReveal.maybeOf(context);
        if (reveal != null) {
          reveal.run(origin: origin, apply: apply);
        } else {
          apply();
        }
      },
    );
  }
}
