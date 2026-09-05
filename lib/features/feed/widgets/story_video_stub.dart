import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Веб бус — blob URL үүсгэх боломжгүй.
String? createBlobUrl(Uint8List bytes, String mime) => null;

/// Веб бус — no-op.
void revokeBlobUrl(String url) {}

/// Веб бус — хугацаа хэмжих боломжгүй.
Future<double?> videoDurationOf(Uint8List bytes, String mime) async => null;

/// Веб бус платформын fallback (апп зөвхөн веб дээр ажилладаг).
class StoryVideoView extends StatelessWidget {
  final String url;
  final double? height;
  final bool loop;
  final bool active;
  final ValueNotifier<bool>? paused;
  final ValueNotifier<bool>? muted;
  final ValueNotifier<double>? progress;
  final ValueChanged<double>? onDuration;
  final VoidCallback? onEnded;
  const StoryVideoView({
    super.key,
    required this.url,
    this.height,
    this.loop = false,
    this.active = true,
    this.paused,
    this.muted,
    this.progress,
    this.onDuration,
    this.onEnded,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_fill_rounded,
            color: Colors.white54, size: 40),
      );
}
