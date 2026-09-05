import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../constants/app_constants.dart';

/// Зураг сонгох + Supabase Storage-д upload хийх (web-compatible)
class ImageUploader {
  static final _picker = ImagePicker();

  /// Gallery-с зураг сонгоод bytes буцаана
  static Future<Uint8List?> pickBytesFromGallery({double maxWidth = 1080}) async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: AppConstants.imageQuality,
      maxWidth: maxWidth,
    );
    if (xFile == null) return null;
    return xFile.readAsBytes();
  }

  /// Camera-с зураг авч bytes буцаана
  static Future<Uint8List?> pickBytesFromCamera() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: AppConstants.imageQuality,
      maxWidth: AppConstants.imageMaxWidth.toDouble(),
    );
    if (xFile == null) return null;
    return xFile.readAsBytes();
  }

  /// Gallery-с видео сонгоод (bytes, ext) буцаана
  static Future<({Uint8List bytes, String ext})?> pickVideo() async {
    final xFile = await _picker.pickVideo(source: ImageSource.gallery);
    if (xFile == null) return null;
    final bytes = await xFile.readAsBytes();
    final name = xFile.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp4';
    return (bytes: bytes, ext: ext);
  }

  /// Supabase Storage-д bytes upload хийж public URL буцаана
  static Future<String?> uploadBytes({
    required Uint8List bytes,
    required String bucket,
    required String path,
    String contentType = 'image/jpeg',
  }) async {
    try {
      await SupabaseService.client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );

      return SupabaseService.client.storage
          .from(bucket)
          .getPublicUrl(path);
    } catch (e) {
      // Алдааг залгиж null буцаадаг гэрээ хэвээр — гэхдээ dev дээр шалтгаан
      // (RLS, буруу bucket, хэт том payload, сүлжээ) харагдана
      if (kDebugMode) debugPrint('uploadBytes [$bucket/$path] failed: $e');
      return null;
    }
  }

  /// Post зураг upload — bucket: posts
  static Future<String?> uploadPost(Uint8List bytes) async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return uploadBytes(
      bytes:  bytes,
      bucket: 'posts',
      path:   '${user.id}/$ts.jpg',
    );
  }

  /// Avatar upload — timestamp-тай зам: URL солигдсоноор browser/CDN/
  /// CachedNetworkImage кэш хуучин аватараа үзүүлсээр байх багаас сэргийлнэ
  static Future<String?> uploadAvatar(Uint8List bytes) async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return uploadBytes(
      bytes:  bytes,
      bucket: 'avatars',
      path:   '${user.id}/avatar_$ts.jpg',
    );
  }

  /// Story media upload — bucket: stories (зураг эсвэл видео)
  static Future<String?> uploadStory(
    Uint8List bytes, {
    String ext = 'jpg',
    String contentType = 'image/jpeg',
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return uploadBytes(
      bytes:  bytes,
      bucket: 'stories',
      path:   '${user.id}/$ts.$ext',
      contentType: contentType,
    );
  }
}
