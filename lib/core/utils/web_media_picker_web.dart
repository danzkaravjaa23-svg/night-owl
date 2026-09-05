// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Веб дээр найдвартай зураг сонголт — HTML file input (image_picker-ийн оронд).
Future<Uint8List?> pickImageBytes() async {
  return _pick('image/*').then((r) => r?.bytes);
}

/// Камераар зураг авах — гар утсан дээр камер шууд нээгдэнэ (capture),
/// компьютер дээр файл сонгоно.
Future<Uint8List?> pickCameraPhoto() async {
  return _pick('image/*', capture: true).then((r) => r?.bytes);
}

/// Веб дээр найдвартай видео сонголт — (bytes, ext) буцаана.
Future<({Uint8List bytes, String ext})?> pickVideoBytes() async {
  final r = await _pick('video/*');
  if (r == null) return null;
  final name = r.name;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp4';
  return (bytes: r.bytes, ext: ext);
}

Future<({Uint8List bytes, String name})?> _pick(String accept,
    {bool capture = false}) async {
  final input = html.FileUploadInputElement()..accept = accept;
  if (capture) input.setAttribute('capture', 'environment'); // мобайл: камер
  // Хэрэглэгч dialog-оо файл сонгохгүй хаавал change event хэзээ ч ирэхгүй —
  // тиймээс change/cancel/focus гурвыг уралдуулж Future заавал дуусгана.
  final done = Completer<void>();
  final subs = <StreamSubscription>[];
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  subs.add(input.onChange.listen((_) => finish()));
  // Орчин үеийн browser-ууд (Chrome 113+/Safari 16.4+/FF 91+) cancel илгээдэг
  subs.add(input.on['cancel'].listen((_) => finish()));
  // Хуучин browser fallback: dialog хаагдаж цонх focus эргэж ирсний дараа
  // богино хугацаанд файл сонгогдоогүй бол цуцлагдсанд тооцно
  subs.add(html.window.onFocus.listen((_) {
    Future.delayed(const Duration(milliseconds: 700), () {
      if (input.files == null || input.files!.isEmpty) finish();
    });
  }));
  input.click();
  await done.future;
  for (final s in subs) {
    s.cancel();
  }
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  final f = files.first;
  final reader = html.FileReader();
  final c = Completer<Uint8List?>();
  reader.onLoadEnd.listen((_) {
    final res = reader.result;
    if (res is Uint8List) {
      c.complete(res);
    } else if (res is ByteBuffer) {
      c.complete(res.asUint8List());
    } else {
      c.complete(null);
    }
  });
  reader.onError.listen((_) => c.complete(null));
  reader.readAsArrayBuffer(f);
  final bytes = await c.future
      .timeout(const Duration(seconds: 60), onTimeout: () => null);
  if (bytes == null) return null;
  return (bytes: bytes, name: f.name);
}
