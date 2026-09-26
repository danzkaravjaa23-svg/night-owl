import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';

import 'image_uploader.dart' show VideoTooLargeException;

// Native (Android/iOS) дээр image_picker-ээр сонгоно. Цуцалсан/алдаа бол null.
final ImagePicker _picker = ImagePicker();

Future<Uint8List?> pickImageBytes() => _pickImage(ImageSource.gallery);

Future<Uint8List?> pickCameraPhoto() => _pickImage(ImageSource.camera);

Future<({Uint8List bytes, String ext})?> pickVideoBytes() async {
  try {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return null;
    if (await x.length() > VideoTooLargeException.maxBytes) {
      throw const VideoTooLargeException();
    }
    final bytes = await x.readAsBytes();
    final name = x.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp4';
    return (bytes: bytes, ext: ext);
  } on VideoTooLargeException {
    rethrow;
  } catch (e) {
    debugPrint('pickVideoBytes failed: $e');
    return null;
  }
}

Future<Uint8List?> _pickImage(ImageSource source) async {
  try {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (x == null) return null;
    return await x.readAsBytes();
  } catch (e) {
    debugPrint('pickImage($source) failed: $e');
    return null;
  }
}
