/// Таб хаагдах/refresh үед сервер рүү keepalive хүсэлт илгээгч
/// (web=pagehide listener, бусад платформ=no-op).
library;
export 'live_unload_stub.dart'
    if (dart.library.html) 'live_unload_web.dart';
