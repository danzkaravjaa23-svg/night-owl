// Платформоос хамаарсан медиа сонголт.
// Веб дээр HTML file input (image_picker web найдваргүй байдгийг тойрч).
export 'web_media_picker_stub.dart'
    if (dart.library.io) 'web_media_picker_io.dart'
    if (dart.library.html) 'web_media_picker_web.dart';
