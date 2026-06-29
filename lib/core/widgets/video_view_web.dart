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
  const VideoView({
    super.key,
    required this.url,
    this.posterOnly = false,
    this.height,
    this.autoplay = false,
    this.showPosterIcon = true,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'nightowl-video-${_viewCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final v = html.VideoElement()
        ..src = widget.url
        ..controls = !widget.posterOnly && !widget.autoplay
        ..autoplay = widget.autoplay
        ..loop = widget.autoplay
        ..muted = widget.posterOnly || widget.autoplay
        ..setAttribute('playsinline', '')
        ..setAttribute('preload', 'metadata');
      v.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = (widget.posterOnly || widget.autoplay) ? 'cover' : 'contain'
        ..backgroundColor = 'black'
        ..border = 'none';
      // Poster болон autoplay (Reels) дээр товшилтыг Flutter overlay руу
      // дамжуулахын тулд видеог pointer-гүй болгоно (like/comment/устгах ажиллана).
      if (widget.posterOnly || widget.autoplay) v.style.pointerEvents = 'none';
      return v;
    });
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
