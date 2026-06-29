// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Веб дээр HTML5 <audio> элементээр дуу тоглуулна — plugin шаардахгүй тул
/// MissingPluginException гарахгүй, autoplay бодлогод нийцнэ.
class WebAudio {
  html.AudioElement? _el;

  void play(String url, {bool loop = true, double volume = 1.0}) {
    stop();
    final el = html.AudioElement()
      ..src = url
      ..loop = loop
      ..volume = volume
      ..autoplay = true
      ..setAttribute('playsinline', '')
      ..setAttribute('preload', 'auto');
    _el = el;
    // play() нь Promise буцаадаг — autoplay блоклосон бол алдаа залгина
    try {
      el.play().catchError((_) {});
    } catch (_) {}
  }

  void pause() {
    try { _el?.pause(); } catch (_) {}
  }

  void resume() {
    try { _el?.play().catchError((_) {}); } catch (_) {}
  }

  void stop() {
    try {
      _el?.pause();
      _el?.src = '';
    } catch (_) {}
    _el = null;
  }

  void dispose() => stop();
}
