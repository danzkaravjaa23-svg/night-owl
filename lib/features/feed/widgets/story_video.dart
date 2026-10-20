import 'package:flutter/material.dart';
import '../../../core/widgets/authorized_media.dart';
import 'story_video_stub.dart'
    if (dart.library.io) 'story_video_io.dart'
    if (dart.library.html) 'story_video_web.dart' as platform;
export 'story_video_stub.dart'
    if (dart.library.io) 'story_video_io.dart'
    if (dart.library.html) 'story_video_web.dart' hide StoryVideoView;

class StoryVideoView extends StatelessWidget {
  final String url;
  final double? height;
  final bool loop,active;
  final ValueNotifier<bool>? paused,muted;
  final ValueNotifier<double>? progress;
  final ValueChanged<double>? onDuration;
  final VoidCallback? onEnded;
  const StoryVideoView({super.key,required this.url,this.height,this.loop=false,
    this.active=true,this.paused,this.muted,this.progress,this.onDuration,this.onEnded});
  @override
  Widget build(BuildContext context)=>AuthorizedMedia(url:url,builder:(source)=>platform.StoryVideoView(
    url:source,height:height,loop:loop,active:active,paused:paused,muted:muted,
    progress:progress,onDuration:onDuration,onEnded:onEnded));
}
