// Google Map — веб дээр iframe, native дээр flutter_map, бусад дээр url_launcher fallback
export 'google_map_view_stub.dart'
    if (dart.library.io) 'google_map_view_io.dart'
    if (dart.library.html) 'google_map_view_web.dart';
