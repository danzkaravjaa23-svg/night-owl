import '../constants/app_constants.dart';
import 'supabase_service.dart';

/// Only our own Storage origin can request a signed URL using this session.
({String bucket, String path})? protectedStorageObject(String url,
    {String backend = AppConstants.backendUrl}) {
  final uri = Uri.tryParse(url), origin = Uri.tryParse(backend);
  if (uri == null ||
      origin == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.origin != origin.origin) {
    return null;
  }
  final parts = uri.pathSegments;
  if (parts.length < 6 ||
      parts.take(4).join('/') != 'storage/v1/object/public' ||
      !{'posts', 'stories'}.contains(parts[4])) {
    return null;
  }
  return (bucket: parts[4], path: parts.skip(5).join('/'));
}

Future<String> authorizedMediaUrl(String url) async {
  final object = protectedStorageObject(url);
  if (object == null) return url;
  return SupabaseService.client.storage
      .from(object.bucket)
      .createSignedUrl(object.path, 300);
}
