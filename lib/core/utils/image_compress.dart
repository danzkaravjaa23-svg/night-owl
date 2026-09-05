/// Платформоос хамаарсан зураг compress (web=canvas JPEG, бусад=өөрчлөлтгүй).
library;
export 'image_compress_stub.dart'
    if (dart.library.html) 'image_compress_web.dart';
