// Камер нээх — веб дээр getUserMedia, бусад дээр null (image_picker fallback)
export 'story_camera_stub.dart'
    if (dart.library.html) 'story_camera_web.dart';
