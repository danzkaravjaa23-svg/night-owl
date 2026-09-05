// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _storyVideoCounter = 0;

/// Bytes-ээс түр blob URL үүсгэнэ (сонгосон видеог урьдчилан харах)
String? createBlobUrl(Uint8List bytes, String mime) =>
    html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime));

/// Blob URL-ыг чөлөөлнө
void revokeBlobUrl(String url) {
  try { html.Url.revokeObjectUrl(url); } catch (_) {}
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
    try { html.Url.revokeObjectUrl(url); } catch (_) {}
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
  State<StoryVideoView> createState() => _StoryVideoViewState();
}

class _StoryVideoViewState extends State<StoryVideoView> {
  late final String _viewType;
  html.VideoElement? _video;
  final List<StreamSubscription> _subs = [];

  bool get _isPausedByUser => widget.paused?.value ?? false;
  bool get _isMuted => widget.muted?.value ?? true;

  void _safePlay(html.VideoElement v) {
    v.play().catchError((_) {
      // Дуутай autoplay блоклогдвол muted-аар үргэлжлүүлнэ
      v.muted = true;
      v.play().catchError((_) {});
    });
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'nightowl-story-video-${_storyVideoCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final v = html.VideoElement()
        ..src = widget.url
        ..autoplay = widget.active && !_isPausedByUser
        ..loop = widget.loop
        // muted autoplay үргэлж зөвшөөрөгддөг — идэвхгүй бол заавал muted
        ..muted = !widget.active || _isMuted
        ..setAttribute('playsinline', '')
        ..setAttribute('preload', 'auto');
      v.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'cover'
        ..backgroundColor = 'black'
        ..border = 'none'
        ..pointerEvents = 'none'; // товшилт Flutter overlay руу дамжина
      _video = v;
      _subs.add(v.onLoadedMetadata.listen((_) {
        final d = v.duration;
        if (d.isFinite && d > 0) widget.onDuration?.call(d.toDouble());
      }));
      if (widget.onEnded != null) {
        _subs.add(v.onEnded.listen((_) => widget.onEnded?.call()));
      }
      final prog = widget.progress;
      if (prog != null) {
        _subs.add(v.onTimeUpdate.listen((_) {
          final d = v.duration;
          if (d.isFinite && d > 0) {
            prog.value = (v.currentTime / d).clamp(0.0, 1.0).toDouble();
          }
        }));
      }
      return v;
    });
    widget.paused?.addListener(_onPausedChanged);
    widget.muted?.addListener(_onMutedChanged);
  }

  void _onPausedChanged() {
    final v = _video;
    if (v == null) return;
    if (_isPausedByUser) {
      v.pause();
    } else if (widget.active) {
      _safePlay(v);
    }
  }

  void _onMutedChanged() {
    final v = _video;
    if (v == null || !widget.active) return;
    v.muted = _isMuted;
    if (!_isMuted && v.paused && !_isPausedByUser) _safePlay(v);
  }

  @override
  void didUpdateWidget(covariant StoryVideoView old) {
    super.didUpdateWidget(old);
    final v = _video;
    if (v == null || widget.active == old.active) return;
    // Идэвхтэй нь дуутай тоглож, идэвхгүй нь чимээгүй зогсоно
    if (widget.active && !_isPausedByUser) {
      v.muted = _isMuted;
      _safePlay(v);
    } else {
      v.pause();
      v.muted = true;
    }
  }

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    widget.paused?.removeListener(_onPausedChanged);
    widget.muted?.removeListener(_onMutedChanged);
    // DOM-оос хасагдсан media элемент өөрөө pause хийдэггүй — дууг таслана
    _video?.pause();
    _video?.src = '';
    _video = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: widget.height,
        width: double.infinity,
        color: Colors.black,
        child: HtmlElementView(viewType: _viewType),
      );
}
