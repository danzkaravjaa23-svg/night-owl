import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Browser нь Web Share API (navigator.share + canShare) дэмждэг эсэх.
/// Дэмжихгүй бол (жишээ нь desktop Firefox) share_plus mailto: нээдэг —
/// тиймээс false үед холбоосыг шууд clipboard руу хуулна.
bool webShareSupported() {
  try {
    final nav = globalContext['navigator'] as JSObject?;
    return nav != null && nav.has('share') && nav.has('canShare');
  } catch (_) {
    return false;
  }
}
