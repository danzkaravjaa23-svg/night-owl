// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'story_video_status.dart';

const _storyVideoViewType = 'nightowl-story-video';
int _storyVideoCounter = 0;
bool _storyVideoFactoryRegistered = false;
final Map<String, _StoryVideoViewState> _liveStoryVideos = {};

// One browser-lifetime factory resolves only live instances. Removing a state
// on dispose releases its DOM, callbacks and widget without growing the registry.
void _registerStoryVideo() {
  if (_storyVideoFactoryRegistered) return;
  ui_web.platformViewRegistry.registerViewFactory(
      _storyVideoViewType,
      (int _, {Object? params}) =>
          _liveStoryVideos[params]?._createElement() ?? html.DivElement());
  _storyVideoFactoryRegistered = true;
}

/// Bytes-ээс түр blob URL үүсгэнэ (сонгосон видеог урьдчилан харах)
String? createBlobUrl(Uint8List bytes, String mime) =>
    html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));

/// Blob URL-ыг чөлөөлнө
void revokeBlobUrl(String url) {
  try {
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}

/// Видеоны үргэлжлэх хугацааг (сек) metadata-аас хэмжинэ
Future<double?> videoDurationOf(Uint8List bytes, String mime) async {
  final url = html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));
  final v = html.VideoElement()..preload = 'metadata';
  try {
    v.src = url;
    await v.onLoadedMetadata.first.timeout(const Duration(seconds: 8));
    final d = v.duration;
    return (d.isFinite && d > 0) ? d.toDouble() : null;
  } catch (_) {
    return null;
  } finally {
    v.src = '';
    try {
      html.Url.revokeObjectUrl(url);
    } catch (_) {}
  }
}

/// Story/Reel видео — pause/mute notifier, duration/ended callback-тай
/// бүрэн удирдлагатай HTML5 <video>.
/// Browser дуутай autoplay-г блоклодог тул үргэлж muted эхэлж,
/// хэрэглэгчийн эхний gesture дээр muted notifier-оор дуу нээгдэнэ.
class StoryVideoView extends StatefulWidget {
  final String url;
  final double? height;
  final bool loop;

  /// Reels: харагдаж буй хуудас л тоглоно
  final bool active;

  /// true → түр зогсооно (hold-to-pause, дээр нь өөр дэлгэц нээгдэх г.м.)
  final ValueNotifier<bool>? paused;

  /// Дуу хаах/нээх (null → үргэлж muted)
  final ValueNotifier<bool>? muted;

  /// Тоглуулах явц 0..1
  final ValueNotifier<double>? progress;

  /// Metadata ачаалагдахад бодит үргэлжлэх хугацаа (сек)
  final ValueChanged<double>? onDuration;

  /// loop=false үед видео дуусахад
  final VoidCallback? onEnded;
  final VoidCallback? onRetry;
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
    this.onRetry,
  });

  @override
  State<StoryVideoView> createState() => _StoryVideoViewState();
}

class _StoryVideoViewState extends State<StoryVideoView> {
  late final String _instanceKey;
  html.VideoElement? _video;
  final List<StreamSubscription> _subs = [];
  Timer? _loadTimer;
  bool _ready = false;
  bool _failed = false;
  int _generation = 0;

  bool get _isPausedByUser => widget.paused?.value ?? false;
  bool get _isMuted => widget.muted?.value ?? true;
  bool _current(html.VideoElement v, int generation) =>
      mounted && identical(v, _video) && generation == _generation;

  void _safePlay(html.VideoElement v) {
    final generation = _generation;
    v.play().then((_) {
      if (!_current(v, generation) ||
          !widget.active ||
          _isPausedByUser ||
          _failed) {
        v.pause();
      }
    }).catchError((_) {
      if (!_current(v, generation) ||
          !widget.active ||
          _isPausedByUser ||
          _failed) {
        return;
      }
      // An autoplay-policy rejection is distinct from a media load failure.
      v.muted = true;
      v.play().then((_) {
        if (!_current(v, generation) ||
            !widget.active ||
            _isPausedByUser ||
            _failed) {
          v.pause();
        }
      }).catchError((_) {});
    });
  }

  @override
  void initState() {
    super.initState();
    _instanceKey = '${_storyVideoCounter++}';
    _liveStoryVideos[_instanceKey] = this;
    _registerStoryVideo();
    widget.paused?.addListener(_onPausedChanged);
    widget.muted?.addListener(_onMutedChanged);
  }

  html.VideoElement _createElement() {
    final v = html.VideoElement()
      ..setAttribute('playsinline', '')
      ..setAttribute('preload', 'auto');
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..backgroundColor = 'black'
      ..border = 'none'
      ..pointerEvents = 'none';
    _video = v;
    _open(v);
    return v;
  }

  void _open(html.VideoElement v) {
    final generation = ++_generation;
    _loadTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _ready = false;
    _failed = false;
    v.pause();
    v
      ..autoplay = widget.active && !_isPausedByUser
      ..loop = widget.loop
      ..muted = !widget.active || _isMuted;
    _subs.add(v.onLoadedData.listen((_) {
      if (!_current(v, generation) || _failed) return;
      _loadTimer?.cancel();
      setState(() => _ready = true);
    }));
    _subs.add(v.onError.listen((_) => _fail(v, generation)));
    _subs.add(v.onLoadedMetadata.listen((_) {
      if (!_current(v, generation)) return;
      final d = v.duration;
      if (d.isFinite && d > 0) widget.onDuration?.call(d.toDouble());
    }));
    _subs.add(v.onEnded.listen((_) {
      if (_current(v, generation) && !widget.loop) widget.onEnded?.call();
    }));
    _subs.add(v.onTimeUpdate.listen((_) {
      if (!_current(v, generation)) return;
      final d = v.duration;
      if (d.isFinite && d > 0) {
        widget.progress?.value = (v.currentTime / d).clamp(0.0, 1.0).toDouble();
      }
    }));
    _loadTimer = Timer(const Duration(seconds: 15), () => _fail(v, generation));
    v.src = widget.url;
    v.load();
    if (widget.active && !_isPausedByUser) _safePlay(v);
  }

  void _fail(html.VideoElement v, int generation) {
    if (!_current(v, generation) || _failed) return;
    _loadTimer?.cancel();
    v.pause();
    setState(() => _failed = true);
  }

  void _retry() {
    if (widget.onRetry != null) {
      widget.onRetry!();
    } else if (_video != null) {
      setState(() => _open(_video!));
    }
  }

  void _onPausedChanged() {
    final v = _video;
    if (v == null || _failed) return;
    if (_isPausedByUser) {
      v.pause();
    } else if (widget.active) {
      _safePlay(v);
    }
  }

  void _onMutedChanged() {
    final v = _video;
    if (v == null || !widget.active || _failed) return;
    v.muted = _isMuted;
    if (!_isMuted && v.paused && !_isPausedByUser) _safePlay(v);
  }

  @override
  void didUpdateWidget(covariant StoryVideoView old) {
    super.didUpdateWidget(old);
    if (old.paused != widget.paused) {
      old.paused?.removeListener(_onPausedChanged);
      widget.paused?.addListener(_onPausedChanged);
    }
    if (old.muted != widget.muted) {
      old.muted?.removeListener(_onMutedChanged);
      widget.muted?.addListener(_onMutedChanged);
    }
    final v = _video;
    if (v == null) return;
    if (old.url != widget.url) {
      _open(v);
      return;
    }
    v.loop = widget.loop;
    v.muted = !widget.active || _isMuted;
    if (!widget.active || _isPausedByUser || _failed) {
      v.pause();
    } else if (widget.active != old.active || widget.paused != old.paused) {
      _safePlay(v);
    }
  }

  @override
  void dispose() {
    _generation++;
    _loadTimer?.cancel();
    _liveStoryVideos.remove(_instanceKey);
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    widget.paused?.removeListener(_onPausedChanged);
    widget.muted?.removeListener(_onMutedChanged);
    final v = _video;
    _video = null;
    v?.pause();
    v?.removeAttribute('src');
    v?.load();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: widget.height,
        width: double.infinity,
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          HtmlElementView(
              viewType: _storyVideoViewType, creationParams: _instanceKey),
          if (!_ready || _failed)
            StoryVideoStatus(failed: _failed, onRetry: _retry),
        ]),
      );
}
