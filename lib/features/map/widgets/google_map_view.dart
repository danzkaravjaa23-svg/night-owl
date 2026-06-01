// Google Map — веб дээр iframe, бусад дээр url_launcher fallback
export 'google_map_view_stub.dart'
    if (dart.library.html) 'google_map_view_web.dart';
