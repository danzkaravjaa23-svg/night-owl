// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../services/media_access.dart';

const _videoViewType = 'nightowl-video';
int _viewCounter = 0;
bool _videoFactoryRegistered = false;
final Map<String, _VideoViewState> _liveStates = {};

void _registerVideoFactory() {
  if (_videoFactoryRegistered) return;
  ui_web.platformViewRegistry.registerViewFactory(
      _videoViewType,
      (int _, {Object? params}) =>
          _liveStates[params]?._createElement() ?? html.DivElement());
  _videoFactoryRegistered = true;
}

/// Веб дээр native HTML5 <video> элемент — webm/mp4/mov-г browser кодекоор
/// найдвартай тоглуулж, эхний кадрыг автоматаар poster болгоно.
class VideoView extends StatefulWidget {
  final String url;
  final bool posterOnly;
  final double? height;
  final bool autoplay;
  final bool showPosterIcon;
  final bool active;
  final ValueNotifier<double>? progress;

  /// Persistent Flutter play/pause control with keyboard and semantics support.
  final bool showControls;

  /// Хүрээг дүүргэж тайрах (IG feed шиг 4:5 хайрцагт хар зурвасгүй).
  /// false бол бүтэн видео харагдана (contain) — пост дэлгэрэнгүйд.
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

class _VideoViewState extends State<VideoView> {
  late final String _instanceKey;
  html.VideoElement? _video; // дуу/тоглуулалт удирдахад
  StreamSubscription? _gestureSub;
  StreamSubscription? _timeSub;
  StreamSubscription? _playSub;
  StreamSubscription? _pauseSub;
  StreamSubscription? _renewalSub;
  int _sourceGeneration = 0;
  bool _restoringPosition = false;
  bool _playing = false; // товшилтын overlay (play badge) харуулах эсэх

  @override
  void didUpdateWidget(covariant VideoView old) {
    super.didUpdateWidget(old);
    final v = _video;
    if (v == null) return;
    // Жагсаалт recycle хийгдэж өөр пост энэ слотод орж ирвэл —
    // хуучин видео биш ШИНЭ url-ийг ачаална (wrong-media баг)
    if (widget.url != old.url) {
      final renewal = sameProtectedMediaObject(old.url, widget.url);
      final position = renewal && v.currentTime.isFinite ? v.currentTime : 0.0;
      final wasPlaying = !v.paused;
      final generation = ++_sourceGeneration;
      _renewalSub?.cancel();
      v.pause();
      if (!renewal) widget.progress?.value = 0;
      _restoringPosition = renewal;
      if (renewal) {
        _renewalSub = v.onLoadedMetadata.listen((_) {
          if (!mounted ||
              generation != _sourceGeneration ||
              !identical(v, _video)) {
            return;
          }
          v.currentTime =
              v.duration.isFinite ? position.clamp(0, v.duration) : position;
          _restoringPosition = false;
          if (wasPlaying &&
              widget.active &&
              (ModalRoute.of(context)?.isCurrent ?? true)) {
            v.play();
          } else {
            v.pause();
          }
          _renewalSub?.cancel();
        });
      }
      final reelMuted = widget.autoplay && !widget.active;
      v
        ..src = widget.url
        ..controls = false
        ..autoplay = renewal ? wasPlaying : widget.autoplay
        ..loop = widget.autoplay
        ..muted = widget.posterOnly || reelMuted;
      v.style.objectFit = (widget.posterOnly || widget.autoplay || widget.cover)
          ? 'cover'
          : 'contain';
      // Контролгүй үед DOM элемент товшилт залгихгүй — Flutter давхарга авна
      v.style.pointerEvents = 'none';
      _playing =
          false; // шинэ url — build аль хэдийн явж байгаа тул setState-гүй
      if (!renewal && widget.autoplay && widget.active) v.play();
    }
    // Reel идэвхжих/идэвхгүйжихэд — идэвхтэй нь дуутай тоглож, бусад нь зогсоно
    if (!widget.autoplay) return;
    if (widget.active != old.active) {
      if (widget.active) {
        v.muted = false;
        v.play();
      } else {
        v.pause();
        v.muted = true;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _instanceKey = '${_viewCounter++}';
    _liveStates[_instanceKey] = this;
    _registerVideoFactory();

    // Browser нь дуутай autoplay-г заримдаа блоклодог — хэрэглэгчийн анхны
    // товшилт дээр идэвхтэй reel-ийг unmute хийж тоглуулна (дуу гаргана).
    if (widget.autoplay) {
      _gestureSub = html.document.onClick.listen((_) {
        final v = _video;
        if (v == null || !mounted || !widget.active) return;
        // Дээр нь өөр route нээлттэй (comments, profile) үед дуу гаргахгүй
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
        if (v.paused) {
          v.muted = false;
          v.play();
        }
      });
    }
  }

  html.VideoElement _createElement() {
    // Reel: зөвхөн идэвхтэй нь дуутай. Poster (grid) үргэлж дуугүй.
    final reelMuted = widget.autoplay && !widget.active;
    final v = html.VideoElement()
      ..src = widget.url
      ..controls = false
      ..autoplay = widget.autoplay
      ..loop = widget.autoplay
      ..muted = widget.posterOnly || reelMuted
      ..setAttribute('playsinline', '')
      ..setAttribute('preload', 'metadata');
    _video = v;
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = (widget.posterOnly || widget.autoplay || widget.cover)
          ? 'cover'
          : 'contain'
      ..backgroundColor = 'black'
      ..border = 'none';
    // Native контрол хэрэглэхгүй бол товшилтыг Flutter overlay руу
    // дамжуулахын тулд видеог pointer-гүй болгоно (like/comment/устгах ажиллана).
    v.style.pointerEvents = 'none';
    // Play/pause төлөв — товшилтын overlay-ийн badge үүнээс хамаарна
    _playSub?.cancel();
    _playSub = v.onPlay.listen((_) {
      if (mounted && !_playing) setState(() => _playing = true);
    });
    _pauseSub?.cancel();
    _pauseSub = v.onPause.listen((_) {
      if (mounted && _playing) setState(() => _playing = false);
    });
    // Тоглуулах явцыг (0..1) гадагш дамжуулна — reel-ийн доод progress bar.
    // widget.progress-ийг динамикаар уншина (recycle дээр notifier солигдож болно),
    // mounted шалгалт нь dispose хийгдсэн notifier руу бичихээс хамгаална.
    _timeSub?.cancel();
    _timeSub = v.onTimeUpdate.listen((_) {
      if (!mounted || _restoringPosition) return;
      final prog = widget.progress;
      if (prog == null) return;
      final d = v.duration;
      if (d.isFinite && d > 0) {
        prog.value = (v.currentTime / d).clamp(0.0, 1.0).toDouble();
      }
    });
    return v;
  }

  /// Товшилтоор тоглуулах/зогсоох (Instagram маяг) — native контролын оронд
  void _togglePlay() {
    final v = _video;
    if (v == null) return;
    if (v.paused) {
      v.muted = false;
      v.play();
    } else {
      v.pause();
    }
  }

  @override
  void dispose() {
    _gestureSub?.cancel();
    _timeSub?.cancel();
    _playSub?.cancel();
    _pauseSub?.cancel();
    _renewalSub?.cancel();
    _sourceGeneration++;
    _liveStates.remove(_instanceKey);
    // DOM элементийг идэвхгүйжүүлж сүлжээ/дуу суллана
    final v = _video;
    if (v != null) {
      v.pause();
      v.removeAttribute('src');
      v.load();
    }
    _video = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view =
        HtmlElementView(viewType: _videoViewType, creationParams: _instanceKey);

    if (widget.posterOnly) {
      return Stack(fit: StackFit.expand, children: [
        Container(color: Colors.black),
        view,
        if (widget.showPosterIcon) ...[
          const IgnorePointer(
              child: Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white, size: 34))),
          const Positioned(
              top: 6,
              right: 6,
              child: IgnorePointer(
                  child: Icon(Icons.videocam_rounded,
                      color: Colors.white70, size: 16))),
        ],
      ]);
    }

    // Өндөр: эцэг нь хатуу хүрээ өгсөн бол (ж: AspectRatio, grid нүд) түүнийг
    // дүүргэнэ; үгүй бол дамжуулсан height, эс бөгөөс 360 нөөц утга.
    return LayoutBuilder(builder: (ctx, c) {
      return Container(
        height: c.hasBoundedHeight ? null : (widget.height ?? 360),
        width: double.infinity,
        color: Colors.black,
        child: widget.showControls
            ? Stack(fit: StackFit.expand, children: [
                view,
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton.filled(
                      tooltip: _playing ? 'Түр зогсоох' : 'Тоглуулах',
                      onPressed: _togglePlay,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(_playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                    ),
                  ),
                ),
              ])
            // Native контролгүй. Зөвхөн ТӨВИЙН play товч товшилт авна —
            // бусад талбар нь эцэг рүү дамжина, ингэснээр картын onTap (пост
            // нээх) ба onDoubleTap (лайк) зураг дээрхтэй яг адилхан ажиллана.
            // Тоглож эхэлмэгц товч алга болж, товшилт бүхэлдээ эцэгт очно.
            : Stack(fit: StackFit.expand, children: [
                view,
                IgnorePointer(
                  ignoring: _playing,
                  child: AnimatedOpacity(
                    opacity: _playing ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Center(
                      // 56 нүд, гэхдээ 44-ийн доод хязгаарт нийцсэн дарах талбай
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _togglePlay,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 32),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
      );
    });
  }
}
