// Веб бус fallback (энэ апп веб дээр ажилладаг) — юу ч хийхгүй.

/// Сонгосон медиа файл — веб дээр html.File wrap хийнэ
class PickedMediaFile {
  final Object? file;
  final String previewUrl;
  final bool isVideo;
  const PickedMediaFile(this.file, this.previewUrl, this.isVideo);

  String get name => '';
  int get size => 0;
  String get mimeType => '';
}

/// Файл сонгох диалог — cancel бол хоосон list
Future<List<PickedMediaFile>> pickPostMedia({bool multiple = true}) async =>
    const [];

/// Preview object URL чөлөөлөх
void revokePreviewUrl(String url) {}

/// Зураг resize + JPEG compress — upload хийх blob буцаана
Future<Object> resizeImageForUpload(PickedMediaFile media,
        {int maxDim = 1440, num quality = 0.82}) async =>
    Object();

/// Blob хэмжээ (byte)
int blobSize(Object blob) => 0;

/// XHR streaming upload — progress callback-тай
Future<void> uploadBlobWithProgress({
  required Object blob,
  required String url,
  required String token,
  required String mime,
  void Function(double progress)? onProgress,
}) async {}
