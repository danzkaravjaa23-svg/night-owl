// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _viewCounter = 0;

/// viewType → амьд State холбоос. Factory closure-ууд State-ийг шууд
/// капчурлахгүй (зөвхөн string түлхүүр) — dispose дээр эндээс устгаснаар
/// урт scroll session-д State/DOM leak үүсэхгүй.
final Map<String, _VideoViewState> _liveStates = {};

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

  /// Browser-ийн native <video> контрол бар (play/scrub/volume/fullscreen)
  /// харуулах эсэх. Фийд/пост дээр ҮРГЭЛЖ false — саарал HTML5 бар неон
  /// картын дотор эвгүй харагдаад зогсохгүй, картын товшилтыг ч залгидаг.
  /// Оронд нь медиа дээрх Flutter давхарга товшилтоор play/pause хийнэ.
  final bool showControls;
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
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final String _viewType;
  html.VideoElement? _video; // дуу/тоглуулалт удирдахад
  StreamSubscription? _gestureSub;
  StreamSubscription? _timeSub;
  StreamSubscription? _playSub;
  StreamSubscription? _pauseSub;
  bool _playing = false; // товшилтын overlay (play badge) харуулах эсэх

  @override
  void didUpdateWidget(covariant VideoView old) {
    super.didUpdateWidget(old);
    final v = _video;
    if (v == null) return;
    // Жагсаалт recycle хийгдэж өөр пост энэ слотод орж ирвэл —
    // хуучин видео биш ШИНЭ url-ийг ачаална (wrong-media баг)
    if (widget.url != old.url) {
      v.pause();
      widget.progress?.value = 0;
      final reelMuted = widget.autoplay && !widget.active;
      v
        ..src = widget.url
        ..controls = widget.showControls
        ..autoplay = widget.autoplay
        ..loop = widget.autoplay
        ..muted = widget.posterOnly || reelMuted;
      v.style.objectFit =
          (widget.posterOnly || widget.autoplay) ? 'cover' : 'contain';
      // Контролгүй үед DOM элемент товшилт залгихгүй — Flutter давхарга авна
      v.style.pointerEvents = widget.showControls ? 'auto' : 'none';
      _playing = false; // шинэ url — build аль хэдийн явж байгаа тул setState-гүй
      if (widget.autoplay && widget.active) v.play();
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
    _viewType = 'nightowl-video-${_viewCounter++}';
    _liveStates[_viewType] = this;
    // Closure нь зөвхөн локал string + глобал map капчурлана (State-ийг биш)
    final vt = _viewType;
    ui_web.platformViewRegistry.registerViewFactory(vt, (int _) {
      final state = _liveStates[vt];
      if (state == null) return html.DivElement(); // State аль хэдийн үхсэн
      return state._createElement();
    });

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
      ..controls = widget.showControls
      ..autoplay = widget.autoplay
      ..loop = widget.autoplay
      ..muted = widget.posterOnly || reelMuted
      ..setAttribute('playsinline', '')
      ..setAttribute('preload', 'metadata');
    _video = v;
    v.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = (widget.posterOnly || widget.autoplay) ? 'cover' : 'contain'
      ..backgroundColor = 'black'
      ..border = 'none';
    // Native контрол хэрэглэхгүй бол товшилтыг Flutter overlay руу
    // дамжуулахын тулд видеог pointer-гүй болгоно (like/comment/устгах ажиллана).
    if (!widget.showControls) v.style.pointerEvents = 'none';
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
      if (!mounted) return;
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
    _liveStates.remove(_viewType);
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
    final view = HtmlElementView(viewType: _viewType);

    if (widget.posterOnly) {
      return Stack(fit: StackFit.expand, children: [
        Container(color: Colors.black),
        view,
        if (widget.showPosterIcon) ...[
          const IgnorePointer(child: Center(child: Icon(
              Icons.play_circle_fill_rounded, color: Colors.white, size: 34))),
          const Positioned(top: 6, right: 6, child: IgnorePointer(
              child: Icon(Icons.videocam_rounded, color: Colors.white70, size: 16))),
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
          ? view
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
