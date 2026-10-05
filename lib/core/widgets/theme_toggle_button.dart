import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import 'glass_icon_button.dart';

/// Quick access complements the day/night/system choice in Settings.
class ThemeToggleButton extends ConsumerWidget {
  final bool onMedia;
  const ThemeToggleButton({super.key, this.onMedia = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassIconButton(
      icon: dark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
      iconColor: dark ? const Color(0xFFFFCF78) : AppColors.accentStart,
      onMedia: onMedia,
      tooltip: dark ? 'Өдрийн горимд шилжих' : 'Шөнийн горимд шилжих',
      onTap: () async {
        try {
          await ref
              .read(themeModeProvider.notifier)
              .setMode(dark ? ThemeMode.light : ThemeMode.dark);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Өнгөний горим хадгалж чадсангүй. Дахин оролдоно уу.'),
            ));
          }
        }
      },
    );
  }
}
