import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get _global;
@JS('document')
external _Document get _document;
extension type _Document(JSObject _) implements JSObject {
  external _Script createElement(String tag);
  external _Head? get head;
}
extension type _Head(JSObject _) implements JSObject {
  external void appendChild(_Script element);
}
extension type _Script(JSObject _) implements JSObject {
  external set src(String value);
  @JS('async')
  external set isAsync(bool value);
  external set onload(JSFunction? value);
  external set onerror(JSFunction? value);
  external void remove();
}

bool get _ready => _global.getProperty<JSAny?>('AppleID'.toJS) != null;
Future<void>? _loading;

/// Load only after an explicit Apple authorization action. URL is fixed to
/// Apple's documented SDK; no nonce, identity token or code enters the URL.
Future<void> ensureAppleWebSdk() {
  if (_ready) return Future.value();
  return _loading ??= _load().catchError((Object error) {
    _loading = null;
    throw error;
  });
}

Future<void> _load() async {
  final script = _document.createElement('script');
  final done = Completer<void>();
  script.src =
      'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';
  script.isAsync = true;
  script.onload = ((JSAny? _) {
    if (done.isCompleted) return;
    if (_ready) {
      done.complete();
    } else {
      done.completeError(StateError('Apple authorization SDK unavailable'));
    }
  }).toJS;
  script.onerror = ((JSAny? _) {
    if (!done.isCompleted) {
      done.completeError(StateError('Apple authorization SDK unavailable'));
    }
  }).toJS;
  try {
    final head = _document.head;
    if (head == null) throw StateError('Apple authorization SDK unavailable');
    head.appendChild(script);
    await done.future.timeout(const Duration(seconds: 15));
  } finally {
    script.onload = null;
    script.onerror = null;
    if (!_ready) script.remove();
  }
}
