// Пост үүсгэх медиа сонголт/боловсруулалт/upload — платформ хамааралтай хэсэг.
// dart:html зөвхөн _web файлд (web_audio.dart-ийн conditional import загвар).
export 'post_media_stub.dart'
    if (dart.library.html) 'post_media_web.dart';
