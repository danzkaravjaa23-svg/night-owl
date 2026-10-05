import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

/// Native encoding matches the JPEG extension and content-type sent to storage.
Future<Uint8List> compressToJpeg(Uint8List bytes,
    {int maxDim = 1440, num quality = 0.82}) => compute(_encode,
      (bytes: bytes, maxDim: maxDim, quality: quality));

Uint8List _encode(({Uint8List bytes, int maxDim, num quality}) request) {
  final decoded = image.decodeImage(request.bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  var resized = image.bakeOrientation(decoded);
  if (resized.width > request.maxDim || resized.height > request.maxDim) {
    resized = image.copyResize(resized,
      width: resized.width >= resized.height ? request.maxDim : null,
      height: resized.height > resized.width ? request.maxDim : null);
  }
  return image.encodeJpg(resized, quality: (request.quality * 100).round().clamp(1, 100));
}
