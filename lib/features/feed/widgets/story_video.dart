import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/media_access.dart';
import '../../auth/providers/auth_provider.dart';
import 'story_video_status.dart';
import 'story_video_stub.dart'
    if (dart.library.io) 'story_video_io.dart'
    if (dart.library.html) 'story_video_web.dart' as platform;
export 'story_video_stub.dart'
    if (dart.library.io) 'story_video_io.dart'
    if (dart.library.html) 'story_video_web.dart' hide StoryVideoView;

class StoryVideoView extends ConsumerStatefulWidget {
  final String url;
  final double? height;
  final bool loop, active;
  final ValueNotifier<bool>? paused, muted;
  final ValueNotifier<double>? progress;
  final ValueChanged<double>? onDuration;
  final VoidCallback? onEnded;
  const StoryVideoView(
      {super.key,
      required this.url,
      this.height,
      this.loop = false,
      this.active = true,
      this.paused,
      this.muted,
      this.progress,
      this.onDuration,
      this.onEnded});
  @override
  ConsumerState<StoryVideoView> createState() => _StoryVideoViewState();
}

class _StoryVideoViewState extends ConsumerState<StoryVideoView> {
  String? _identity;
  Future<String>? _source;
  int _attempt = 0;

  void _retry() => setState(() {
        _attempt++;
        _identity = null;
      });

  @override
  Widget build(BuildContext context) {
    final protected = protectedStorageObject(widget.url) != null;
    final account = protected ? ref.watch(sessionUserIdProvider) : null;
    final identity = '$account:${widget.url}:$_attempt';
    Widget player(String source) => platform.StoryVideoView(
        key: ValueKey(identity),
        url: source,
        height: widget.height,
        loop: widget.loop,
        active: widget.active,
        paused: widget.paused,
        muted: widget.muted,
        progress: widget.progress,
        onDuration: widget.onDuration,
        onEnded: widget.onEnded,
        onRetry: _retry);
    if (!protected) return player(widget.url);
    if (_identity != identity) {
      _identity = identity;
      _source =
          authorizedMediaUrl(widget.url).timeout(const Duration(seconds: 15));
    }
    return FutureBuilder<String>(
      key: ValueKey(identity),
      future: _source,
      builder: (context, snapshot) => snapshot.hasData
          ? player(snapshot.data!)
          : SizedBox(
              height: widget.height,
              child:
                  StoryVideoStatus(failed: snapshot.hasError, onRetry: _retry)),
    );
  }
}
