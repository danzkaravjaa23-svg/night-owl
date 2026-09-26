import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

const _kTmpPrefix = 'nightowl_story_';
int _tmpCounter = 0;
bool _tmpSwept = false;

void _quiet(Future<void> f) {
  f.then<void>((_) {}, onError: (Object _) {});
}

String _tmpDirPath() {
  final p = Directory.systemTemp.path;
  return p.endsWith(Platform.pathSeparator) ? p.substring(0, p.length - 1) : p;
}

String _extFor(String mime) => switch (mime.split(';').first.trim().toLowerCase()) {
      'video/quicktime' => '.mov',
      'video/webm' => '.webm',
      'video/x-matroska' => '.mkv',
      _ => '.mp4',
    };

bool _isOurTmp(String path) =>
    !path.contains('..') &&
    path.startsWith('${_tmpDirPath()}${Platform.pathSeparator}$_kTmpPrefix');

// Апп хаагдаж revoke хийгдээгүй үлдсэн түр файлуудыг нэг удаа цэвэрлэнэ
void _sweepStaleTmp(Directory dir) {
  if (_tmpSwept) return;
  _tmpSwept = true;
  try {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    for (final e in dir.listSync(followLinks: false)) {
      if (e is File &&
          e.path.split(Platform.pathSeparator).last.startsWith(_kTmpPrefix) &&
          e.lastModifiedSync().isBefore(cutoff)) {
        e.deleteSync();
      }
    }
  } catch (_) {}
}

String _newTmpPath(String mime) {
  final dir = Directory(_tmpDirPath());
  if (!dir.existsSync()) dir.createSync(recursive: true);
  _sweepStaleTmp(dir);
  return '${dir.path}${Platform.pathSeparator}$_kTmpPrefix'
      '${_tmpCounter++}_${DateTime.now().microsecondsSinceEpoch}${_extFor(mime)}';
}

/// Bytes-ийг түр файлд бичиж замыг нь буцаана (веб blob URL-ын оронд)
String? createBlobUrl(Uint8List bytes, String mime) {
  try {
    final path = _newTmpPath(mime);
    File(path).writeAsBytesSync(bytes, flush: true);
    return path;
  } catch (_) {
    return null;
  }
}

/// createBlobUrl-ын түр файлыг устгана
void revokeBlobUrl(String url) {
  try {
    if (!_isOurTmp(url)) return;
    final f = File(url);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

/// Видеоны үргэлжлэх хугацааг (сек) player-ээр хэмжинэ
Future<double?> videoDurationOf(Uint8List bytes, String mime) async {
  String? path;
  VideoPlayerController? c;
  try {
    path = _newTmpPath(mime);
    await File(path).writeAsBytes(bytes, flush: true);
    c = VideoPlayerController.file(File(path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    await c.initialize().timeout(const Duration(seconds: 8));
    final d = c.value.duration;
    return d > Duration.zero
        ? d.inMicroseconds / Duration.microsecondsPerSecond
        : null;
  } catch (_) {
    return null;
  } finally {
    if (c != null) _quiet(c.dispose());
    if (path != null) revokeBlobUrl(path);
  }
}

/// Story/Reel видео — веб хувилбартай ижил семантиктай native (video_player) хувилбар.
class StoryVideoView extends StatefulWidget {
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
  State<StoryVideoView> createState() => _StoryVideoViewState();
}

class _StoryVideoViewState extends State<StoryVideoView> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _durationSent = false;
  bool _endedSent = false;

  bool get _isPausedByUser => widget.paused?.value ?? false;
  bool get _isMuted => widget.muted?.value ?? true;

  @override
  void initState() {
    super.initState();
    widget.paused?.addListener(_onPausedChanged);
    widget.muted?.addListener(_onMutedChanged);
    _open();
  }

  VideoPlayerController? _controllerFor(String url) {
    try {
      final opts = VideoPlayerOptions(mixWithOthers: true);
      final uri = Uri.tryParse(url);
      final scheme = uri?.scheme.toLowerCase() ?? '';
      if (uri != null && (scheme == 'http' || scheme == 'https')) {
        return VideoPlayerController.networkUrl(uri, videoPlayerOptions: opts);
      }
      final path = (uri != null && scheme == 'file') ? uri.toFilePath() : url;
      return VideoPlayerController.file(File(path), videoPlayerOptions: opts);
    } catch (_) {
      return null;
    }
  }

  void _open() {
    _ready = false;
    _durationSent = false;
    _endedSent = false;
    final c = _controllerFor(widget.url);
    if (c == null) return;
    _ctrl = c;
    // Initialize-ээс өмнөх тохиргоог controller хадгалж, бэлэн болмогц хэрэглэнэ
    _quiet(c.setLooping(widget.loop));
    _quiet(c.setVolume(!widget.active || _isMuted ? 0 : 1));
    if (widget.active && !_isPausedByUser) _quiet(c.play());
    c.addListener(_onTick);
    c.initialize().then<void>((_) {
      if (mounted && _ctrl == c) _onTick();
    }, onError: (Object _) {});
  }

  void _close() {
    final c = _ctrl;
    _ctrl = null;
    if (c == null) return;
    c.removeListener(_onTick);
    _quiet(c.pause());
    _quiet(c.dispose());
  }

  void _onTick() {
    final c = _ctrl;
    if (c == null || !mounted) return;
    final v = c.value;
    // Хойшлогдсон play() (seek await) дараа ирсэн pause-ийг дарахаас сэргийлнэ
    if (v.isPlaying && (!widget.active || _isPausedByUser)) _quiet(c.pause());
    if (v.isInitialized != _ready) setState(() => _ready = v.isInitialized);
    if (!v.isInitialized) return;
    final d = v.duration;
    if (d > Duration.zero) {
      if (!_durationSent) {
        _durationSent = true;
        widget.onDuration
            ?.call(d.inMicroseconds / Duration.microsecondsPerSecond);
      }
      final prog = widget.progress;
      if (prog != null) {
        prog.value = (v.position.inMicroseconds / d.inMicroseconds)
            .clamp(0.0, 1.0)
            .toDouble();
      }
    }
    // Веб 'ended'-тэй адил: loop үед дуудагдахгүй, төгсгөлд хүрэх бүрт нэг удаа
    if (v.isCompleted) {
      if (!_endedSent && !widget.loop) {
        _endedSent = true;
        widget.onEnded?.call();
      }
    } else if (v.isPlaying) {
      // Дууссаны дараах хоцорсон position update дахин дуудуулахгүй
      _endedSent = false;
    }
  }

  void _onPausedChanged() {
    final c = _ctrl;
    if (c == null) return;
    if (_isPausedByUser) {
      _quiet(c.pause());
    } else if (widget.active) {
      _quiet(c.play());
    }
  }

  void _onMutedChanged() {
    final c = _ctrl;
    if (c == null || !widget.active) return;
    _quiet(c.setVolume(_isMuted ? 0 : 1));
    if (!_isMuted && !c.value.isPlaying && !_isPausedByUser) _quiet(c.play());
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
    if (old.url != widget.url) {
      _close();
      _open();
      return;
    }
    final c = _ctrl;
    if (c == null) return;
    if (old.loop != widget.loop) _quiet(c.setLooping(widget.loop));
    if (widget.active == old.active) return;
    // Идэвхтэй нь дуутай тоглож, идэвхгүй нь чимээгүй зогсоно
    if (widget.active && !_isPausedByUser) {
      _quiet(c.setVolume(_isMuted ? 0 : 1));
      _quiet(c.play());
    } else {
      _quiet(c.pause());
      _quiet(c.setVolume(0));
    }
  }

  @override
  void dispose() {
    widget.paused?.removeListener(_onPausedChanged);
    widget.muted?.removeListener(_onMutedChanged);
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    Widget? video;
    if (c != null && _ready) {
      final s = c.value.size;
      // Веб дээрх object-fit: cover
      video = (s.width > 0 && s.height > 0)
          ? FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                  width: s.width, height: s.height, child: VideoPlayer(c)))
          : VideoPlayer(c);
    }
    return Container(
      height: widget.height,
      width: double.infinity,
      color: Colors.black,
      child: SizedBox.expand(child: video),
    );
  }
}
