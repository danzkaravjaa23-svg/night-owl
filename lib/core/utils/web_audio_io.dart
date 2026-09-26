import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:video_player/video_player.dart';

/// Native дээр video_player (ExoPlayer)-оор дуу тоглуулна — web_audio_web.dart-тай
/// ижил API. Алдааг залгиж debugPrint хийнэ.
class WebAudio {
  VideoPlayerController? _ctrl;
  // stop()/play() бүрт нэмэгдэнэ — хуучирсан initialize-ийн үргэлжлэлийг таслана
  int _gen = 0;
  bool _wantPlaying = false;

  void play(String url, {bool loop = true, double volume = 1.0}) {
    stop();
    final gen = _gen;
    final VideoPlayerController c;
    try {
      c = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    } catch (e) {
      debugPrint('WebAudio.play($url) failed: $e');
      return;
    }
    _ctrl = c;
    _wantPlaying = true;
    unawaited(_start(c, gen, loop, volume));
  }

  Future<void> _start(
      VideoPlayerController c, int gen, bool loop, double volume) async {
    try {
      await c.initialize();
      if (gen != _gen) return;
      await c.setLooping(loop);
      if (gen != _gen) return;
      await c.setVolume(volume);
      if (gen != _gen || !_wantPlaying) return;
      await c.play();
    } catch (e) {
      debugPrint('WebAudio.play failed: $e');
      if (gen == _gen && identical(_ctrl, c)) {
        _ctrl = null;
        _wantPlaying = false;
        unawaited(_release(c));
      }
    }
  }

  void pause() {
    _wantPlaying = false;
    final c = _ctrl;
    if (c != null && c.value.isInitialized) unawaited(_guard(c.pause));
  }

  void resume() {
    final c = _ctrl;
    if (c == null) return;
    _wantPlaying = true;
    if (c.value.isInitialized) unawaited(_guard(c.play));
  }

  void stop() {
    _gen++;
    _wantPlaying = false;
    final c = _ctrl;
    _ctrl = null;
    if (c != null) unawaited(_release(c));
  }

  void dispose() => stop();

  static Future<void> _release(VideoPlayerController c) =>
      _guard(c.dispose);

  static Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('WebAudio: $e');
    }
  }
}
