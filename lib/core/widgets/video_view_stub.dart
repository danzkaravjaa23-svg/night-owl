import 'package:flutter/material.dart';

/// Веб бус платформын fallback (одоо зөвхөн web дээр ажиллаж байгаа).
class VideoView extends StatelessWidget {
  final String url;
  final bool posterOnly;
  final double? height;
  final bool autoplay;
  final bool showPosterIcon;
  final bool active;
  final ValueNotifier<double>? progress;
  const VideoView({
    super.key,
    required this.url,
    this.posterOnly = false,
    this.height,
    this.autoplay = false,
    this.showPosterIcon = true,
    this.active = true,
    this.progress,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: posterOnly ? null : (height ?? 360),
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_fill_rounded,
            color: Colors.white54, size: 40),
      );
}
