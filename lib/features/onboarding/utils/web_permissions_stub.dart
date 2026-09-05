/// Веб бус платформын fallback (одоо зөвхөн web дээр ажиллаж байгаа).
class WebPermissions {
  /// Байршлын зөвшөөрөл асуух — no-op
  static Future<void> requestLocation() async {}

  /// Мэдэгдлийн зөвшөөрөл асуух — no-op
  static Future<void> requestNotification() async {}
}
