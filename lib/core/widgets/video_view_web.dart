import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _viewCounter = 0;

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
  const VideoView({
    super.key,
    required this.url,
    this.posterOnly = false,
    this.height,
    this.autoplay = false,
    this.showPosterIcon = true,
    this.active = true,
    this.progress,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final String _viewType;
  html.VideoElement? _video; // дуу/тоглуулалт удирдахад
  StreamSubscription? _gestureSub;

  @override
  void didUpdateWidget(covariant VideoView old) {
    super.didUpdateWidget(old);
    // Reel идэвхжих/идэвхгүйжихэд — идэвхтэй нь дуутай тоглож, бусад нь зогсоно
    final v = _video;
    if (v == null || !widget.autoplay) return;
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
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      // Reel: зөвхөн идэвхтэй нь дуутай. Poster (grid) үргэлж дуугүй.
      final reelMuted = widget.autoplay && !widget.active;
      final v = html.VideoElement()
        ..src = widget.url
        ..controls = !widget.posterOnly && !widget.autoplay
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
      // Poster болон autoplay (Reels) дээр товшилтыг Flutter overlay руу
      // дамжуулахын тулд видеог pointer-гүй болгоно (like/comment/устгах ажиллана).
      if (widget.posterOnly || widget.autoplay) v.style.pointerEvents = 'none';
      // Тоглуулах явцыг (0..1) гадагш дамжуулна — reel-ийн доод progress bar.
      final prog = widget.progress;
      if (prog != null) {
        v.onTimeUpdate.listen((_) {
          final d = v.duration;
          if (d.isFinite && d > 0) {
            prog.value = (v.currentTime / d).clamp(0.0, 1.0).toDouble();
          }
        });
      }
      return v;
    });

    // Browser нь дуутай autoplay-г заримдаа блоклодог — хэрэглэгчийн анхны
    // товшилт дээр идэвхтэй reel-ийг unmute хийж тоглуулна (дуу гаргана).
    if (widget.autoplay) {
      _gestureSub = html.document.onClick.listen((_) {
        final v = _video;
        if (v != null && widget.active && v.paused) {
          v.muted = false;
          v.play();
        }
      });
    }
  }

  @override
  void dispose() {
    _gestureSub?.cancel();
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

    return Container(
      height: widget.height ?? 360,
      width: double.infinity,
      color: Colors.black,
      child: view,
    );
  }
}
