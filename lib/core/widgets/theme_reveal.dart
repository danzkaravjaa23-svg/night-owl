import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Горим солиход шинэ өнгө нь товшсон цэгээс ТОЙРОГ болон тэлж
/// бүх дэлгэцийг бүрхэнэ (Telegram маягийн circular reveal).
///
/// Ажиллах зарчим: солихын өмнө одоогийн дэлгэцийн зургийг авч дээр нь
/// тавина → горимыг солино (доор нь шинэ өнгөөр зурагдана) → хуучин
/// зургийн голд өсөх нүх гаргаж шинийг ил болгоно.
///
/// Зураг авч чадахгүй (платформ) эсвэл "хөдөлгөөн багасгах" асаалттай
/// бол зүгээр шууд солино — эвдрэлгүй.
class ThemeReveal extends StatefulWidget {
  final Widget child;
  const ThemeReveal({super.key, required this.child});

  static ThemeRevealState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ThemeRevealState>();

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundaryKey = GlobalKey();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  ui.Image? _snapshot;
  Offset _origin = Offset.zero;
  bool _busy = false;

  /// [origin] — дэлгэцийн (global) координат, ихэвчлэн toggle-ийн төв.
  /// [apply] — жинхэнэ горим солих үйлдэл.
  Future<void> run({
    required Offset? origin,
    required Future<void> Function() apply,
  }) async {
    if (_busy) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (reduceMotion || boundary == null || origin == null) {
      await apply();
      return;
    }

    _busy = true;
    var applied = false;
    try {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: dpr);
      if (!mounted) {
        image.dispose();
        return;
      }
      final box = context.findRenderObject() as RenderBox;
      setState(() {
        _snapshot = image;
        _origin = box.globalToLocal(origin);
      });

      await apply();
      applied = true;
      // 1) горимын rebuild, 2) бүх элементийг дахин зурах pass
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _c.forward(from: 0);
    } catch (_) {
      if (!applied) await apply();
    } finally {
      final old = _snapshot;
      if (mounted) {
        setState(() => _snapshot = null);
        _c.value = 0;
      }
      old?.dispose();
      _busy = false;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    // Бүтэц нь үргэлж ижил (Stack) — child дахин mount хийгдэхгүй.
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (snap != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  painter: _RevealPainter(
                    image: snap,
                    origin: _origin,
                    t: Curves.easeInOutCubic.transform(_c.value),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RevealPainter extends CustomPainter {
  final ui.Image image;
  final Offset origin;
  final double t;

  _RevealPainter({required this.image, required this.origin, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // Эх цэгээс хамгийн алс буланд хүрэх радиус
    final maxR = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - origin).distance).reduce(math.max);
    final radius = maxR * t;

    // Хуучин зураг — голдоо өсөх тойрог нүхтэй
    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: origin, radius: radius)));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    // Тэлж буй ирмэг дээр зөөлөн неон гэрэл
    if (t > 0 && t < 1) {
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFC026D3).withValues(alpha: 0.45 * (1 - t))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.t != t || old.image != image || old.origin != origin;
}
