import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _camCounter = 0;

/// Веб дээр getUserMedia-аар камер нээж, зураг авч bytes буцаана.
Future<Uint8List?> openStoryCamera(BuildContext context) {
  return Navigator.of(context).push<Uint8List?>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const _WebCameraScreen(),
  ));
}

class _WebCameraScreen extends StatefulWidget {
  const _WebCameraScreen();
  @override
  State<_WebCameraScreen> createState() => _WebCameraScreenState();
}

class _WebCameraScreenState extends State<_WebCameraScreen> {
  late final String _viewType;
  html.MediaStream? _stream;
  html.VideoElement? _video;
  bool _ready = false;
  bool _front = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewType = 'story-cam-${_camCounter++}';
    _init();
  }

  Future<void> _init() async {
    try {
      final media = html.window.navigator.mediaDevices;
      if (media == null) {
        setState(() => _error = 'Камер дэмжигдэхгүй');
        return;
      }
      _stream?.getTracks().forEach((t) => t.stop());
      final s = await media.getUserMedia({
        'video': {'facingMode': _front ? 'user' : 'environment'},
        'audio': false,
      });
      _stream = s;
      final v = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', '')
        ..srcObject = s;
      v.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'cover'
        ..transform = _front ? 'scaleX(-1)' : 'none';
      _video = v;
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => v);
      await v.onLoadedMetadata.first
          .timeout(const Duration(seconds: 5), onTimeout: () => html.Event(''));
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Камер нээх боломжгүй.\nЗөвшөөрөл олгоно уу.');
    }
  }

  void _capture() {
    final v = _video;
    if (v == null || v.videoWidth == 0) return;
    final canvas = html.CanvasElement(width: v.videoWidth, height: v.videoHeight);
    final ctx = canvas.context2D;
    if (_front) {
      ctx.translate(v.videoWidth, 0);
      ctx.scale(-1, 1); // толин дүрсийг буцаах
    }
    ctx.drawImage(v, 0, 0);
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.9);
    final bytes = base64Decode(dataUrl.split(',').last);
    _stop();
    if (mounted) Navigator.of(context).pop(Uint8List.fromList(bytes));
  }

  void _stop() => _stream?.getTracks().forEach((t) => t.stop());

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
                GestureDetector(
                  onTap: _ready ? _capture : null,
                  child: Container(
                    width: 74, height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white24,
                      border: Border.all(color: Colors.white, width: 4)),
                    child: const Center(child: Icon(Icons.circle, color: Colors.white, size: 56)))),
                SizedBox(width: 56, child: IconButton(
                  onPressed: () { setState(() { _front = !_front; _ready = false; }); _init(); },
                  icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 28))),
              ])))),
      ]),
    );
  }
}
