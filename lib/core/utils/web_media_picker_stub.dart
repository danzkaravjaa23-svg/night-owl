import 'dart:typed_data';

/// Веб бус fallback (энэ апп веб дээр ажилладаг). null буцаана.
Future<Uint8List?> pickImageBytes() async => null;
Future<Uint8List?> pickCameraPhoto() async => null;
Future<({Uint8List bytes, String ext})?> pickVideoBytes() async => null;
