// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Зургийн bytes-ийг canvas-аар resize + JPEG болгож багасгана.
/// Алдаа гарвал / томров эх bytes-ээ буцаана.
Future<Uint8List> compressToJpeg(Uint8List bytes,
    {int maxDim = 1440, num quality = 0.82}) async {
  try {
    final srcBlob = html.Blob([bytes]);
    final url = html.Url.createObjectUrl(srcBlob);
    final img = html.ImageElement(src: url);
    // Зураг ачаалахыг хүлээнэ — гэхдээ мөнхөд гацахгүйн тулд timeout-той
    await Future.any([
      img.onLoad.first.then((_) => true),
      img.onError.first.then((_) => false),
    ]).timeout(const Duration(seconds: 8), onTimeout: () => false);
    if (img.naturalWidth == 0) { html.Url.revokeObjectUrl(url); return bytes; }
    final w = img.naturalWidth;
    final h = img.naturalHeight;
    html.Url.revokeObjectUrl(url);

    final longest = w > h ? w : h;
    final scale = longest > maxDim ? maxDim / longest : 1.0;
    final tw = (w * scale).round();
    final th = (h * scale).round();

    final canvas = html.CanvasElement(width: tw, height: th);
    // JPEG alpha дэмждэггүй — PNG-ийн тунгалаг хэсэг ХАР болохоос сэргийлж
    // эхлээд цагаанаар дүүргэнэ (ихэнх фото апп alpha-г цагаанаар flatten хийдэг)
    canvas.context2D
      ..fillStyle = '#fff'
      ..fillRect(0, 0, tw, th);
    canvas.context2D.drawImageScaled(img, 0, 0, tw.toDouble(), th.toDouble());

    final outBlob = await canvas.toBlob('image/jpeg', quality);
    final reader = html.FileReader();
    final c = Completer<Uint8List>();
    reader.onLoadEnd.listen((_) {
      final res = reader.result;
      if (res is ByteBuffer) {
        c.complete(res.asUint8List());
      } else if (res is Uint8List) {
        c.complete(res);
      } else {
        c.complete(bytes);
      }
    });
    reader.onError.listen((_) => c.complete(bytes));
    reader.readAsArrayBuffer(outBlob);

    final result = await c.future
        .timeout(const Duration(seconds: 8), onTimeout: () => bytes);
    return result.length < bytes.length ? result : bytes;
  } catch (_) {
    return bytes;
  }
}
