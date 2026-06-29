import 'package:flutter/material.dart';
import 'video_view_stub.dart'
    if (dart.library.html) 'video_view_web.dart';

/// URL видео мөн эсэхийг өргөтгөлөөр шалгах
bool isVideoUrl(String? url) {
  if (url == null) return false;
  final u = url.toLowerCase();
  return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm') ||
      u.endsWith('.m4v') || u.endsWith('.avi') || u.endsWith('.mkv');
}

/// Сүлжээний видео.
/// posterOnly=true (grid): эхний кадр + play icon, tap эцэг рүү дамжина.
/// posterOnly=false (feed/detail): native контролтой, тоглуулна.
class NetworkVideo extends StatelessWidget {
  final String url;
  final bool posterOnly;
  final double? height;
  final bool autoplay;
  final bool showPosterIcon;
  const NetworkVideo({
    super.key,
    required this.url,
    this.posterOnly = false,
    this.height,
    this.autoplay = false,
    this.showPosterIcon = true,
  });

  @override
  Widget build(BuildContext context) =>
      VideoView(url: url, posterOnly: posterOnly, height: height,
          autoplay: autoplay, showPosterIcon: showPosterIcon);
}
