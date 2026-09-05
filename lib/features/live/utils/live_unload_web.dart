// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js_interop';

/// window.fetch — keepalive:true дэмждэг тул pagehide дээр ч хүсэлт явна
@JS('fetch')
external JSPromise<JSAny?> _fetch(JSAny? input, JSAny? init);

/// key → pagehide listener
final Map<String, void Function(html.Event)> _handlers = {};

/// Таб хаагдах/refresh (pagehide) үед keepalive fetch илгээх бүртгэл.
/// Viewer тоолуур, live төлөвийг таб хаахад ч цэвэрлэхэд ашиглана.
void registerUnloadRequest(
  String key, {
  required String url,
  required String method,
  required Map<String, String> headers,
  required String Function() body,
}) {
  unregisterUnloadRequest(key);
  void handler(html.Event _) {
    try {
      _fetch(url.toJS, {
        'method': method,
        'headers': headers,
        'body': body(),
        'keepalive': true,
      }.jsify());
    } catch (_) {}
  }

  _handlers[key] = handler;
  html.window.addEventListener('pagehide', handler);
}

void unregisterUnloadRequest(String key) {
  final h = _handlers.remove(key);
  if (h != null) html.window.removeEventListener('pagehide', h);
}
