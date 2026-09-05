import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Night Owl брэнд тэмдэг — disco/crystal owl зураг (assets/images/owl_logo.png).
/// Зураг хадгалаагүй үед мөнгөлөг шилэн owl медальоноор солигдоно.
class OwlLogoMark extends StatelessWidget {
  final double size;
  const OwlLogoMark({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        // Мөнгөлөг гэрэлтэлт
        Container(
          width: size * 0.8, height: size * 0.8,
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
            BoxShadow(color: Colors.white.withValues(alpha: 0.16),
              blurRadius: size * 0.34, spreadRadius: size * 0.03),
            BoxShadow(color: AppColors.accentStart.withValues(alpha: 0.14),
              blurRadius: size * 0.4, spreadRadius: 1),
          ])),
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.16),
          child: Image.asset('assets/images/owl_logo.png',
            width: size, height: size, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _fallback()),
        ),
      ]),
    );
  }

  Widget _fallback() => Container(
    width: size * 0.82, height: size * 0.82,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [
        Color(0xFFE8E8F0), Color(0xFF9A9AA8), Color(0xFF3A3A44),
      ], stops: [0.0, 0.55, 1.0])),
    child: Center(child: Text('🦉', style: TextStyle(fontSize: size * 0.5))),
  );
}

/// Удаан хөдөлдөг бараан mesh gradient дэвсгэр —
/// баялаг хар, гүн шөнийн ягаан, неон violet өнгөтэй.
class MeshGradientBackground extends StatefulWidget {
  final Widget? child;
  const MeshGradientBackground({super.key, this.child});
  @override
  State<MeshGradientBackground> createState() => _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 18))..repeat();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MeshPainter(_c),
        isComplex: true,
        child: widget.child,
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final Animation<double> t;
  _MeshPainter(this.t) : super(repaint: t);

  // (баазын байрлал x,y фракц, өнгө, радиус фракц, фаз) — chrome/steel ертөнц
  static const _blobs = [
    [0.22, 0.28, 0xFF3C4255, 0.62, 0.0],  // steel
    [0.82, 0.22, 0xFF1B1E28, 0.58, 1.7],  // graphite
    [0.50, 0.72, 0xFF2C3142, 0.70, 3.1],  // cool slate
    [0.15, 0.86, 0xFF101219, 0.55, 4.6],  // near-black
    [0.88, 0.80, 0xFF474D63, 0.50, 2.3],  // silver-steel glow
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Баялаг хар суурь
    canvas.drawRect(Offset.zero & size,
        Paint()..color = AppColors.bgBase);
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
      canvas.drawCircle(c, rad, Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.0),
        ], stops: const [0.0, 0.55, 1.0])
            .createShader(Rect.fromCircle(center: c, radius: rad)));
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => false; // repaint via Animation
}
