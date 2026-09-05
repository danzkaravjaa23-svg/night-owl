// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// Веб хэрэгжилт — dart:html энд л амьдарна (conditional import загвар).
import 'dart:async';
import 'dart:html' as html;

/// Сонгосон медиа файл — html.File + preview object URL
class PickedMediaFile {
  final html.File file;
  final String previewUrl;
  final bool isVideo;
  const PickedMediaFile(this.file, this.previewUrl, this.isVideo);

  String get name => file.name;
  int get size => file.size;
  String get mimeType => file.type;
}

/// Файл сонгох диалог. Cancel хийвэл хоосон list буцаана —
/// window focus + delay guard тул dangling await үлдэхгүй.
Future<List<PickedMediaFile>> pickPostMedia({bool multiple = true}) async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*,video/*'
    ..multiple = multiple;

  final c = Completer<List<PickedMediaFile>>();

  input.onChange.first.then((_) {
    if (c.isCompleted) return;
    final files = input.files ?? const <html.File>[];
    c.complete([
      for (final f in files)
        PickedMediaFile(
            f, html.Url.createObjectUrl(f), f.type.startsWith('video/')),
    ]);
  });

  // Cancel guard: диалог хаагдаж focus эргэж ирснээс хойш 1.2с дотор
  // onChange ирээгүй бол цуцалсан гэж үзнэ
  final focusSub = html.window.onFocus.listen((_) {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!c.isCompleted) c.complete(const []);
    });
  });

  input.click();
  final result = await c.future;
  await focusSub.cancel();
  return result;
}

/// Preview object URL чөлөөлөх
void revokePreviewUrl(String url) => html.Url.revokeObjectUrl(url);

/// Зураг resize + JPEG compress (canvas).
/// 500к scale — түүхий 5–20MB зургийг ~1440px / JPEG q0.82 болгож
/// багасгана (ихэвчлэн 200–600KB). Decode алдаа/гацвал (эвдэрсэн файл,
/// HEIC support-гүй browser) onError + 15с timeout → эх файлаараа буцаана.
Future<Object> resizeImageForUpload(PickedMediaFile media,
    {int maxDim = 1440, num quality = 0.82}) async {
  final file = media.file;
  final objUrl = html.Url.createObjectUrl(file);
  try {
    final img = html.ImageElement(src: objUrl);
    // onLoad + onError уралдаан + timeout — мөнхөд гацахгүй
    await Future.any([
      img.onLoad.first,
      img.onError.first
          .then((_) => throw Exception('Зураг уншиж чадсангүй')),
    ]).timeout(const Duration(seconds: 15));

    final w = img.naturalWidth;
    final h = img.naturalHeight;
    if (w == 0 || h == 0) return file;

    final longest = w > h ? w : h;
    final scale = longest > maxDim ? maxDim / longest : 1.0;
    final tw = (w * scale).round();
    final th = (h * scale).round();

    final canvas = html.CanvasElement(width: tw, height: th);
    final ctx = canvas.context2D;
    ctx.drawImageScaled(img, 0, 0, tw.toDouble(), th.toDouble());

    final blob = await canvas.toBlob('image/jpeg', quality);
    // Хэрэв ямар нэг шалтгаанаар томрсон бол эх файлаа хэрэглэнэ
    if (blob.size >= file.size && scale == 1.0) return file;
    return blob;
  } catch (_) {
    return file; // fallback — эх файл
  } finally {
    html.Url.revokeObjectUrl(objUrl);
  }
}

/// Blob хэмжээ (byte)
int blobSize(Object blob) => blob is html.Blob ? blob.size : 0;

/// XHR streaming upload — progress callback-тай
Future<void> uploadBlobWithProgress({
  required Object blob,
  required String url,
  required String token,
  required String mime,
  void Function(double progress)? onProgress,
}) async {
  final completer = Completer<void>();
  final xhr = html.HttpRequest()
    ..open('POST', url)
    ..setRequestHeader('Authorization', 'Bearer $token')
    ..setRequestHeader('Content-Type', mime)
    ..setRequestHeader('x-upsert', 'true');

  xhr.upload.onProgress.listen((e) {
    if (e.lengthComputable && onProgress != null) {
      onProgress((e.loaded ?? 0) / (e.total ?? 1));
    }
  });
  xhr.onLoad.listen((_) {
    final s = xhr.status ?? 0;
    if (s >= 200 && s < 300) {
      completer.complete();
    } else if (s == 413) {
      completer.completeError('Файл хэтэрхий том байна — сервер хүлээж авсангүй');
    } else {
      completer.completeError('Илгээхэд алдаа гарлаа ($s)');
    }
  });
  xhr.onError.listen((_) => completer.completeError(
      'Сүлжээний алдаа — интернэт холболтоо шалгана уу'));
  xhr.send(blob as html.Blob);
  await completer.future;
}
