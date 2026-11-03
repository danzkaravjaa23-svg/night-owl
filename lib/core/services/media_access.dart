import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import 'supabase_service.dart';

/// Only our own Storage origin can request a signed URL using this session.
({String bucket, String path})? protectedStorageObject(String url,
    {String backend = AppConstants.backendUrl}) {
  final uri = Uri.tryParse(url), origin = Uri.tryParse(backend);
  if (uri == null ||
      origin == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      !{'http', 'https'}.contains(origin.scheme) ||
      !uri.hasAuthority ||
      !origin.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.origin != origin.origin) {
    return null;
  }
  final parts = uri.pathSegments;
  if (parts.length < 6 ||
      parts.take(3).join('/') != 'storage/v1/object' ||
      !{'public', 'sign', 'authenticated'}.contains(parts[3]) ||
      !{'posts', 'stories', 'avatars', 'venues'}.contains(parts[4]) ||
      parts.skip(5).any((part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.contains('/') ||
          part.contains('\\'))) {
    return null;
  }
  return (bucket: parts[4], path: parts.skip(5).join('/'));
}

final authorizedMediaSignerProvider =
    Provider<Future<String> Function(String)>((_) => authorizedMediaUrl);
final authorizedMediaClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);

bool sameProtectedMediaObject(String previous, String next) {
  final before = protectedStorageObject(previous);
  return before != null && before == protectedStorageObject(next);
}

Future<String> authorizedMediaUrl(String url) async {
  final object = protectedStorageObject(url);
  if (object == null) return url;
  return SupabaseService.client.storage
      .from(object.bucket)
      .createSignedUrl(object.path, 300);
}
