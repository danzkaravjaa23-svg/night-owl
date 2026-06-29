import 'dart:typed_data';

/// Non-web fallback — өөрчлөлтгүй буцаана.
Future<Uint8List> compressToJpeg(Uint8List bytes,
        {int maxDim = 1440, num quality = 0.82}) async =>
    bytes;
