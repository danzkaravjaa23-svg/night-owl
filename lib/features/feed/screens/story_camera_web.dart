import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _camCounter = 0;

/// Камерын үр дүн — cancel (юу ч хийхгүй) болон unsupported (file picker
/// fallback) хоёрыг ялгана.
class StoryCameraResult {
  final Uint8List? bytes;
  final bool unsupported;
  const StoryCameraResult._(this.bytes, this.unsupported);
  const StoryCameraResult.captured(Uint8List b) : this._(b, false);
  const StoryCameraResult.cancelled() : this._(null, false);
  const StoryCameraResult.unsupported() : this._(null, true);
}

/// Веб дээр getUserMedia-аар камер нээж, зураг авч bytes буцаана.
/// Видеог <canvas> дээр тасралтгүй зурж харуулна — Flutter web (CanvasKit)
/// дээр <video> platform view хар гардаг тул canvas найдвартай.
/// X дарж хаавал cancelled (fallback picker нээгдэхгүй),
/// камер дэмжигдэхгүй бол unsupported буцна.
Future<StoryCameraResult> openStoryCamera(BuildContext context) async {
  final res = await Navigator.of(context).push<StoryCameraResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _WebCameraScreen(),
    ),
  );
  return res ?? const StoryCameraResult.cancelled();
}

class _WebCameraScreen extends StatefulWidget {
  const _WebCameraScreen();
  @override
  State<_WebCameraScreen> createState() => _WebCameraScreenState();
}

class _WebCameraScreenState extends State<_WebCameraScreen> {
  late final String _viewType;
  html.MediaStream? _stream;
  html.VideoElement? _video;      // offscreen — зөвхөн эх сурвалж
  html.CanvasElement? _canvas;    // харагдах гадаргуу (platform view)
  int _rafId = 0;
  bool _ready = false;
  bool _front = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewType = 'story-cam-${_camCounter++}';
    // Харагдах canvas-ыг build-ээс ӨМНӨ бүртгэнэ
    final c = html.CanvasElement();
    c.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..pointerEvents = 'none'
      ..backgroundColor = 'black';
    _canvas = c;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => c);
    // Offscreen видео
    _video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', '');
    _init();
  }

  Future<void> _init() async {
    try {
      final media = html.window.navigator.mediaDevices;
      if (media == null) {
        // Камер огт дэмжигдэхгүй — дуудагч file picker fallback ажиллуулна
        if (mounted) {
          Navigator.of(context).pop(const StoryCameraResult.unsupported());
        }
        return;
      }
      _stream?.getTracks().forEach((t) => t.stop());
      final s = await media.getUserMedia({
        'video': {'facingMode': _front ? 'user' : 'environment'},
        'audio': false,
      });
      _stream = s;
      final v = _video!;
      v.srcObject = s;
      try { v.play(); } catch (_) {}
      await v.onLoadedMetadata.first
          .timeout(const Duration(seconds: 5), onTimeout: () => html.Event(''));
      if (mounted) setState(() { _ready = true; _error = null; });
      _startDraw();
    } catch (_) {
      if (mounted) setState(() => _error = 'Камер нээх боломжгүй.\nЗөвшөөрөл олгоно уу.');
    }
  }

  // Видеог canvas дээр тасралтгүй зурна (rAF loop)
  void _startDraw() {
    html.window.cancelAnimationFrame(_rafId);
    void tick(num _) {
      final v = _video, c = _canvas;
      if (v != null && c != null && v.videoWidth > 0) {
        if (c.width != v.videoWidth) {
          c.width = v.videoWidth;
          c.height = v.videoHeight;
        }
        final ctx = c.context2D;
        ctx.save();
        if (_front) {
          ctx.translate(c.width!.toDouble(), 0);
          ctx.scale(-1, 1); // урд камер — толин дүрс
        }
        ctx.drawImage(v, 0, 0);
        ctx.restore();
      }
      _rafId = html.window.requestAnimationFrame(tick);
    }
    _rafId = html.window.requestAnimationFrame(tick);
  }

  void _capture() {
    final c = _canvas;
    if (c == null || (c.width ?? 0) == 0) return;
    // Canvas аль хэдийн толиноор (front) зурсан тул шууд уншина
    final dataUrl = c.toDataUrl('image/jpeg', 0.9);
    final bytes = base64Decode(dataUrl.split(',').last);
    _stop();
    if (mounted) {
      Navigator.of(context)
          .pop(StoryCameraResult.captured(Uint8List.fromList(bytes)));
    }
  }

  void _stop() {
    html.window.cancelAnimationFrame(_rafId);
    _stream?.getTracks().forEach((t) => t.stop());
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_error != null)
          Center(child: Padding(padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15))))
        else
          HtmlElementView(viewType: _viewType),

        // Дээд: хаах
        SafeArea(child: Align(alignment: Alignment.topLeft, child: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton(
            onPressed: () { _stop(); Navigator.of(context).pop(); },
            icon: const Icon(Icons.close, color: Colors.white, size: 26))))),

        // Доод: shutter + flip
        if (_error == null)
          SafeArea(top: false, child: Align(alignment: Alignment.bottomCenter,
            child: Padding(padding: const EdgeInsets.only(bottom: 30),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(width: 56),
                MouseRegion(
                  cursor: _ready
                      ? SystemMouseCursors.click : SystemMouseCursors.basic,
                  child: GestureDetector(
                  onTap: _ready ? _capture : null,
                  child: Container(
                    width: 74, height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white24,
                      border: Border.all(color: Colors.white, width: 4)),
                    child: const Center(child: Icon(Icons.circle, color: Colors.white, size: 56))))),
                SizedBox(width: 56, child: IconButton(
                  onPressed: () { setState(() { _front = !_front; _ready = false; }); _init(); },
                  icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 28))),
              ])))),
      ]),
    );
  }
}
