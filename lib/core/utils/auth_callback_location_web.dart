import 'dart:js_interop';
import 'auth_callback.dart';

@JS('history.replaceState')
external void _replaceState(JSAny? state, JSString unused, JSString url);

void replaceAuthCallbackLocation(Uri uri) {
  _replaceState(null, ''.toJS, cleanAuthCallbackUrl(uri).toString().toJS);
}
