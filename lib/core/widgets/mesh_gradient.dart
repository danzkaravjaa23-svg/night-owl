import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'night_owl_brand.dart';
import 'app_motion.dart';

/// Shared approved owl mark for authentication and onboarding screens.
class OwlLogoMark extends StatelessWidget {
  final double size;
  const OwlLogoMark({super.key, this.size = 120});
  @override
  Widget build(BuildContext context) => NightOwlMark(size: size);
}

/// Удаан хөдөлдөг бараан mesh gradient дэвсгэр —
/// баялаг хар, гүн шөнийн ягаан, неон violet өнгөтэй.
class MeshGradientBackground extends StatefulWidget {
  final Widget? child;

  /// Үргэлж харанхуй дэлгэц (нүүр хуудас) — горимоос үл хамааран шөнийн дэвсгэр.
  final bool forceDark;
  const MeshGradientBackground({super.key, this.child, this.forceDark = false});
  @override
  State<MeshGradientBackground> createState() => _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c =
        AnimationController(vsync: this, duration: const Duration(seconds: 18));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) || !TickerMode.of(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MeshPainter(_c,
            isDark: widget.forceDark ||
                Theme.of(context).brightness == Brightness.dark),
        isComplex: true,
        child: widget.child,
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final Animation<double> t;
  final bool isDark;
  _MeshPainter(this.t, {required this.isDark}) : super(repaint: t);

  // (баазын байрлал x,y фракц, өнгө, радиус фракц, фаз) — chrome/steel ертөнц
  static const _blobs = [
    [0.22, 0.28, 0xFF3C4255, 0.62, 0.0], // steel
    [0.82, 0.22, 0xFF1B1E28, 0.58, 1.7], // graphite
    [0.50, 0.72, 0xFF2C3142, 0.70, 3.1], // cool slate
    [0.15, 0.86, 0xFF101219, 0.55, 4.6], // near-black
    [0.88, 0.80, 0xFF474D63, 0.50, 2.3], // silver-steel glow
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Баялаг хар суурь (цайвар горимд cream — bgBase адаптив)
    canvas.drawRect(Offset.zero & size,
        Paint()..color = isDark ? AppColors.bgBaseDark : AppColors.bgBaseLight);
    // Цайвар горимд бараан steel бөмбөлгүүд cream дээр бохир саарал толбо
    // болохоос сэргийлж зөөлрүүлнэ. Харанхуй горимд 1.0 — өөрчлөлтгүй.
    final k = isDark ? 1.0 : 0.35;
    final v = t.value * 2 * math.pi;
    for (final b in _blobs) {
      final baseX = b[0] as double, baseY = b[1] as double;
      final color = Color(b[2] as int);
      final rad = (b[3] as double) * size.width;
      final phase = b[4] as double;
      // Төв нь удаан, нарийн далайцтай хөдөлнө
      final dx = math.sin(v + phase) * size.width * 0.08;
      final dy = math.cos(v * 0.8 + phase) * size.height * 0.06;
      final c = Offset(baseX * size.width + dx, baseY * size.height + dy);
      // RadialGradient shader — MaskFilter.blur(80)-тай бараг ижил зөөлөн бөмбөлөг,
      // гэхдээ frame бүрт 5 фулл-скрин Gaussian blur хийхгүй (сул төхөөрөмжид чухал)
      canvas.drawCircle(
          c,
          rad,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: 0.30 * k),
              color.withValues(alpha: 0.18 * k),
              color.withValues(alpha: 0.0),
            ], stops: const [
              0.0,
              0.55,
              1.0
            ]).createShader(Rect.fromCircle(center: c, radius: rad)));
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.isDark != isDark || old.t != t;
}
