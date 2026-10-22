import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme_provider.dart';
import 'eclipse_theme_toggle.dart';
import 'theme_reveal.dart';

/// Апп-ын горимтой холбогдсон хиртэлтийн toggle.
/// Дарахад шинэ горим toggle-ийн төвөөс тойрог болон тэлнэ ([ThemeReveal]).
class ThemeToggleButton extends ConsumerStatefulWidget {
  final double width;
  final double height;

  const ThemeToggleButton({super.key, this.width = 60, this.height = 30});

  @override
  ConsumerState<ThemeToggleButton> createState() => _ThemeToggleButtonState();
}

class _ThemeToggleButtonState extends ConsumerState<ThemeToggleButton> {
  // Хадгалалт бүтэлгүйтэхэд горим өөрчлөгдөхгүй тул toggle-ийг дахин mount
  // хийж optimistic хөдөлгөөнийг нь бодит горим руу буцаана.
  int _resync = 0;

  Future<void> _change(bool dark) async {
    final notifier = ref.read(themeModeProvider.notifier);
    Future<void> apply() =>
        notifier.setMode(dark ? ThemeMode.dark : ThemeMode.light);

    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : null;
    final reveal = ThemeReveal.maybeOf(context);
    try {
      if (reveal != null) {
        await reveal.run(origin: origin, apply: apply);
      } else {
        await apply();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _resync++);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Өнгөний горим хадгалж чадсангүй. Дахин оролдоно уу.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => EclipseThemeToggle(
        key: ValueKey(_resync),
        isDark: Theme.of(context).brightness == Brightness.dark,
        width: widget.width,
        height: widget.height,
        onChanged: _change,
      );
}
