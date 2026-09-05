// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Веб дээр browser-ийн жинхэнэ permission prompt-уудыг дуудна.
/// Хэрэглэгч татгалзсан ч flow үргэлжилнэ — алдааг залгина.
class WebPermissions {
  /// Байршлын зөвшөөрөл — Geolocation API-г дуудаж browser prompt гаргана
  static Future<void> requestLocation() async {
    try {
      await html.window.navigator.geolocation
          .getCurrentPosition(timeout: const Duration(seconds: 10));
    } catch (_) {
      // Татгалзсан / хугацаа хэтэрсэн — асуудалгүй, дараа map дээр дахин асууна
    }
  }

  /// Мэдэгдлийн зөвшөөрөл — Notification API prompt
  static Future<void> requestNotification() async {
    try {
      if (html.Notification.supported) {
        await html.Notification.requestPermission();
      }
    } catch (_) {}
  }
}
