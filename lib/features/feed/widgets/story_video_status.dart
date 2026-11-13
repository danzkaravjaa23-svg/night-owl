import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Shared native/web loading and recovery surface. Never exposes backend URLs.
class StoryVideoStatus extends StatelessWidget {
  final bool failed;
  final VoidCallback? onRetry;
  const StoryVideoStatus({super.key, this.failed = false, this.onRetry});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
            child: failed
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.videocam_off_outlined,
                        color: Colors.white70, size: 36),
                    const SizedBox(height: 12),
                    const Text('Видео ачаалж чадсангүй',
                        style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 8),
                    // Үргэлж хар гадаргуу (reels, story) — theme-ийн
                    // accentText нь Day горимд хар дээр бүдэг тул Night-ийнх.
                    TextButton.icon(
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.accentTextDark),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Дахин оролдох')),
                  ])
                : const CircularProgressIndicator(
                    semanticsLabel: 'Видео ачаалж байна',
                    color: Colors.white70)),
      );
}
