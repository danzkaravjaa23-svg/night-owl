// Native (Android/iOS) хэрэгжилт — image_picker + dart:io HttpClient.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/image_compress.dart';

const _videoExts = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv', 'avi'};

const _mimeByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heic',
  'gif': 'image/gif',
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'mkv': 'video/x-matroska',
  'avi': 'video/x-msvideo',
};

const _chunkSize = 64 * 1024;

String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

String _ext(String path) {
  final name = _basename(path);
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// Сонгосон медиа файл — XFile + local file path (preview)
class PickedMediaFile {
  final XFile? file;
  final String previewUrl;
  final bool isVideo;
  const PickedMediaFile(this.file, this.previewUrl, this.isVideo);

  String get _path => file?.path ?? previewUrl;

  String get name => _basename(_path);
  int get size {
    try {
      return File(_path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  String get mimeType => _mimeByExt[_ext(_path)] ?? 'application/octet-stream';
}

/// Gallery-с зураг/видео сонгох — cancel бол хоосон list
Future<List<PickedMediaFile>> pickPostMedia({bool multiple = true}) async {
  try {
    final picker = ImagePicker();
    final List<XFile> files;
    if (multiple) {
      files = await picker.pickMultipleMedia(
          maxWidth: 1440, maxHeight: 1440, imageQuality: 82);
    } else {
      final f = await picker.pickMedia(
          maxWidth: 1440, maxHeight: 1440, imageQuality: 82);
      files = f == null ? const <XFile>[] : <XFile>[f];
    }
    return [
      for (final f in files)
        PickedMediaFile(f, f.path, _videoExts.contains(_ext(f.path))),
    ];
  } catch (e) {
    debugPrint('pickPostMedia failed: $e');
    return const [];
  }
}

void revokePreviewUrl(String url) {
  // image_picker scaled_* файлыг ижил замд дахин бичдэг тул cache-ээс хасна
  try {
    PaintingBinding.instance.imageCache.evict(FileImage(File(url)));
  } catch (_) {}
}

/// The uploaded bytes must match the advertised JPEG content type/extension.
Future<Object> resizeImageForUpload(PickedMediaFile media,
    {int maxDim = 1440, num quality = 0.82}) async {
  final path = media.file?.path ?? media.previewUrl;
  final bytes = await File(path).readAsBytes();
  return compressToJpeg(bytes, maxDim: maxDim, quality: quality.toDouble());
}

/// Blob хэмжээ (byte)
int blobSize(Object blob) {
  try {
    if (blob is List<int>) return blob.length;
    if (blob is File) return blob.lengthSync();
    if (blob is XFile) return File(blob.path).lengthSync();
  } catch (_) {}
  return 0;
}

Stream<List<int>> _chunks(List<int> bytes) async* {
  for (var off = 0; off < bytes.length; off += _chunkSize) {
    final end =
        off + _chunkSize < bytes.length ? off + _chunkSize : bytes.length;
    yield bytes is Uint8List
        ? Uint8List.sublistView(bytes, off, end)
        : bytes.sublist(off, end);
  }
}

/// Streaming upload (веб XHR-тэй ижил POST + header) — progress callback-тай
Future<void> uploadBlobWithProgress({
  required Object blob,
  required String url,
  required String token,
  required String mime,
  void Function(double progress)? onProgress,
}) async {
  final List<int>? bytes = blob is List<int> ? blob : null;
  final String? path = blob is File
      ? blob.path
      : blob is XFile
          ? blob.path
          : null;
  if (bytes == null && path == null) {
    throw Exception('Файл уншиж чадсангүй');
  }

  var total = bytes?.length ?? 0;
  if (bytes == null) {
    try {
      total = await File(path!).length();
    } catch (_) {
      throw Exception('Файл уншиж чадсангүй');
    }
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  var status = 0;
  var body = '';
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set('apikey', AppConstants.supabaseAnonKey)
      ..set(HttpHeaders.contentTypeHeader, mime)
      ..set('x-upsert', 'true');
    req.contentLength = total;

    final source = bytes != null ? _chunks(bytes) : File(path!).openRead();
    var sent = 0;
    var reported = 0.0;
    await for (final chunk in source) {
      req.add(chunk);
      await req.flush();
      sent += chunk.length;
      final p = total > 0 ? sent / total : 1.0;
      if (onProgress != null && (p - reported >= 0.005 || sent >= total)) {
        reported = p;
        onProgress(p);
      }
    }

    final res = await req.close();
    status = res.statusCode;
    body = await res.transform(const Utf8Decoder(allowMalformed: true)).join();
  } on FileSystemException {
    throw Exception('Файл уншиж чадсангүй');
  } catch (e) {
    debugPrint('uploadBlobWithProgress failed: $e');
    throw Exception('Сүлжээний алдаа — интернэт холболтоо шалгана уу');
  } finally {
    client.close(force: true);
  }

  if (status >= 200 && status < 300) return;
  // Supabase storage хэмжээ хэтрэхэд 400 + body.statusCode "413" буцааж болно
  if (status == 413 || body.contains('"413"')) {
    throw Exception('Файл хэтэрхий том байна — сервер хүлээж авсангүй');
  }
  var detail = body;
  try {
    final j = jsonDecode(body);
    if (j is Map && j['message'] is String) detail = j['message'] as String;
  } catch (_) {}
  if (detail.length > 200) detail = detail.substring(0, 200);
  throw Exception(
      'Илгээхэд алдаа гарлаа ($status)${detail.isEmpty ? '' : ': $detail'}');
}

/// Preview зураг — local файлаас
ImageProvider previewImageProvider(PickedMediaFile m) =>
    FileImage(File(m.previewUrl));

/// Preview видео — local файлаас
VideoPlayerController previewVideoController(PickedMediaFile m) =>
    VideoPlayerController.file(File(m.previewUrl));
