/// Платформоос хамаарсан browser permission хүсэлт
/// (web=Geolocation/Notification API, бусад=no-op).
/// lib/core/utils/web_audio.dart-тай ижил stub/_web загвар.
library;
export 'web_permissions_stub.dart'
    if (dart.library.html) 'web_permissions_web.dart';
