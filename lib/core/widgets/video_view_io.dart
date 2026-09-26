import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

/// Android/iOS дээр video_player (ExoPlayer/AVPlayer) — API нь веб хувилбартай ижил.
class VideoView extends StatefulWidget {
  final String url;
  final bool posterOnly;
  final double? height;
  final bool autoplay;
  final bool showPosterIcon;
  final bool active;
  final ValueNotifier<double>? progress;

  /// true бол бүх талбайг товшиж play/pause хийнэ (веб дээрх native контролын оронд).
  final bool showControls;
  /// Хүрээг дүүргэж тайрах (cover); false бол бүтэн видео (contain).
  final bool cover;
  const VideoView({
    super.key,
    required this.url,
    this.posterOnly = false,
    this.height,
    this.autoplay = false,
    this.showPosterIcon = true,
    this.active = true,
    this.progress,
    this.showControls = false,
    this.cover = false,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

/// Алдааг залгина — plugin байхгүй (VM тест) эсвэл устсан тоглуулагч дээр унахгүй.
Future<void> _run(Future<void> Function() op) async {
  try {
    await op();
  } catch (_) {}
}

VideoPlayerController _controllerFor(String url, VideoPlayerOptions opts) {
  final lower = url.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return VideoPlayerController.networkUrl(Uri.parse(url),
        videoPlayerOptions: opts);
  }
  if (lower.startsWith('content://') && Platform.isAndroid) {
    return VideoPlayerController.contentUri(Uri.parse(url),
        videoPlayerOptions: opts);
  }
  final path = lower.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
  return VideoPlayerController.file(File(path), videoPlayerOptions: opts);
}

class _VideoViewState extends State<VideoView> {
  VideoPlayerController? _ctrl;
  int _gen = 0; // url солигдсоны дараа хуучин initialize-ийн хариуг үл тоох
  bool _ready = false;
  bool _failed = false;
  bool _playing = false; // товшилтын overlay (play badge) харуулах эсэх
  bool _onstage = true;

  // Reel: зөвхөн идэвхтэй нь дуутай. Poster (grid) controller-гүй.
  bool get _startMuted => widget.autoplay && !widget.active;

  @override
  void initState() {
    super.initState();
    if (!widget.posterOnly) _create();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Дээрээс opaque route нээгдэхэд веб DOM-оос салгаж зогсоодогтой адил
    final onstage = TickerMode.valuesOf(context).enabled;
    if (onstage == _onstage) return;
    _onstage = onstage;
    final c = _ctrl;
    if (c == null) return;
    if (!onstage) {
      _run(c.pause);
    } else if (widget.autoplay && widget.active) {
      _run(c.play);
    }
  }

  @override
  void didUpdateWidget(covariant VideoView old) {
    super.didUpdateWidget(old);
    // Жагсаалт recycle хийгдэж өөр пост энэ слотод орж ирвэл — ШИНЭ url ачаална
    if (widget.url != old.url || widget.posterOnly != old.posterOnly) {
      _release();
      if (widget.url != old.url) widget.progress?.value = 0;
      if (!widget.posterOnly) _create();
      return;
    }
    final c = _ctrl;
    if (c == null) return;
    if (widget.autoplay != old.autoplay) {
      _run(() => c.setLooping(widget.autoplay));
    }
    if (!widget.autoplay) return;
    if (widget.active != old.active || widget.autoplay != old.autoplay) {
      if (widget.active) {
        _run(() async {
          await c.setVolume(1);
          if (_onstage && identical(_ctrl, c)) await c.play();
        });
      } else {
        _run(() async {
          await c.pause();
          await c.setVolume(0);
        });
      }
    }
  }

  void _create() {
    final gen = ++_gen;
    _ready = false;
    _failed = false;
    _playing = false;
    VideoPlayerController? c;
    try {
      c = _controllerFor(
          widget.url, VideoPlayerOptions(mixWithOthers: _startMuted));
    } catch (_) {}
    if (c == null) {
      _failed = true;
      return;
    }
    _ctrl = c;
    c.addListener(_onTick);
    _init(c, gen);
  }

  Future<void> _init(VideoPlayerController c, int gen) async {
    try {
      // initialize-аас өмнө тавибал initialized эвент дээр хэрэгжинэ
      await c.setLooping(widget.autoplay);
      await c.setVolume(_startMuted ? 0 : 1);
      // Энэ зайд dispose болсон бол native тоглуулагч үүсгэхгүй (leak)
      if (gen != _gen) return;
      await c.initialize();
    } catch (_) {
      if (mounted && gen == _gen) setState(() => _failed = true);
      return;
    }
    if (!mounted || gen != _gen) return;
    setState(() => _ready = true);
    if (widget.autoplay && widget.active && _onstage) {
      _run(() async {
        await c.setVolume(1);
        await c.play();
      });
    }
  }

  void _onTick() {
    final c = _ctrl;
    if (c == null || !mounted) return;
    final v = c.value;
    // widget.progress-ийг динамикаар уншина (recycle дээр notifier солигдож болно)
    final prog = widget.progress;
    final d = v.duration.inMilliseconds;
    if (prog != null && v.isInitialized && d > 0) {
      prog.value = (v.position.inMilliseconds / d).clamp(0.0, 1.0).toDouble();
    }
    if (v.hasError && !_failed) {
      setState(() => _failed = true);
    } else if (v.isPlaying != _playing) {
      setState(() => _playing = v.isPlaying);
    }
  }

  void _release() {
    _gen++;
    final c = _ctrl;
    _ctrl = null;
    _ready = false;
    _failed = false;
    _playing = false;
    if (c == null) return;
    c.removeListener(_onTick);
    _run(c.dispose);
  }

  /// Товшилтоор тоглуулах/зогсоох (Instagram маяг)
  void _toggle() {
    final c = _ctrl;
    if (c == null || _failed) return;
    if (c.value.isPlaying) {
      _run(c.pause);
    } else {
      _run(() async {
        await c.setVolume(1);
        await c.play();
      });
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Grid олон нүдтэй — нүд бүрт ExoPlayer үүсгэвэл hardware decoder дуусна
    if (widget.posterOnly) {
      return Stack(fit: StackFit.expand, children: [
        const _Backdrop(),
        if (widget.showPosterIcon) ...[
          const IgnorePointer(child: Center(child: Icon(
              Icons.play_circle_fill_rounded, color: Colors.white, size: 34))),
          const Positioned(top: 6, right: 6, child: IgnorePointer(
              child: Icon(Icons.videocam_rounded, color: Colors.white70, size: 16))),
        ] else
          const IgnorePointer(child: Center(child: Icon(
              Icons.play_arrow_rounded, color: Colors.white38, size: 30))),
      ]);
    }

    // Эцэг хатуу хүрээ өгвөл дүүргэнэ; үгүй бол height, эс бөгөөс 360
    return LayoutBuilder(builder: (ctx, box) {
      return Container(
        height: box.hasBoundedHeight ? null : (widget.height ?? 360),
        width: double.infinity,
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          _surface(),
          if (_playing && !_ready && !_failed)
            const Center(child: SizedBox(width: 28, height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70))),
          widget.showControls ? _controlsOverlay() : _playOverlay(),
        ]),
      );
    });
  }

  Widget _surface() {
    if (_failed) return const _Backdrop(icon: Icons.videocam_off_rounded);
    final c = _ctrl;
    if (c == null || !_ready || !c.value.isInitialized) return const _Backdrop();
    final v = c.value;
    if (widget.cover || widget.autoplay) {
      final w = v.size.width > 0 ? v.size.width : 1.0;
      final h = v.size.height > 0 ? v.size.height : 1.0;
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: w, height: h, child: VideoPlayer(c)),
          ),
        ),
      );
    }
    return Center(
      child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(c)),
    );
  }

  Widget _playBadge() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
        ),
        child: const Icon(Icons.play_arrow_rounded,
            color: Colors.white, size: 32),
      );

  // Зөвхөн төвийн товч товшилт авна — картын onTap/onDoubleTap хэвээр ажиллана
  Widget _playOverlay() {
    final hidden = _playing || _failed;
    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: _playBadge(),
          ),
        ),
      ),
    );
  }

  Widget _controlsOverlay() {
    final hidden = _playing || _failed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: Center(child: _playBadge()),
      ),
    );
  }
}

/// video_view_stub.dart-ийн харанхуй gradient — poster / ачаалж буй / алдаа.
class _Backdrop extends StatelessWidget {
  final IconData? icon;
  const _Backdrop({this.icon});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgElevatedDark, AppColors.bgSurfaceDark],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.accentGradientSoft),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.58),
                Colors.black.withValues(alpha: 0.12),
                Colors.transparent,
              ],
            ),
          ),
        ),
        if (icon != null)
          Center(child: Icon(icon, color: Colors.white54, size: 32)),
      ]),
    );
  }
}
