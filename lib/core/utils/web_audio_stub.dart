/// Веб бус платформын fallback (одоо зөвхөн web дээр ажиллаж байгаа).
/// Plugin-гүй тул MissingPluginException гарахгүй.
class WebAudio {
  void play(String url, {bool loop = true, double volume = 1.0}) {}
  void pause() {}
  void resume() {}
  void stop() {}
  void dispose() {}
}
