import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Монгол гэрийн icon — бөмбөгөр дээвэр, ханын хэвтээ зураас, утаа, улзий хээ.
/// Брэндийн accent градиентаар дүүргэнэ (апп-д тааруулсан).
class GerIcon extends StatelessWidget {
  final double size;
  final List<Color> colors;
  const GerIcon({
    super.key,
    this.size = 26,
    this.colors = const [
      AppColors.accentStart, AppColors.accentMid, AppColors.accentEnd,
    ],
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GerPainter(colors)),
      );
}

class _GerPainter extends CustomPainter {
  final List<Color> colors;
  _GerPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    ).createShader(rect);

    final fill = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final r = w * 0.04; // банд булангийн радиус

    // ── Бөмбөгөр дээвэр (тооно бүхий нам бөмбөгөр) ──
    final roof = Path()
      ..moveTo(w * 0.05, h * 0.53)
      ..quadraticBezierTo(w * 0.50, h * 0.15, w * 0.95, h * 0.53)
      ..close();
    canvas.drawPath(roof, fill);

    // ── Ханын хэвтээ зураас (band-ууд) ──
    RRect bar(double l, double t, double rgt, double b) =>
        RRect.fromRectAndRadius(
            Rect.fromLTRB(w * l, h * t, w * rgt, h * b), Radius.circular(r));

    // 1-р банд — бүтэн өргөн
    canvas.drawRRect(bar(0.13, 0.55, 0.87, 0.64), fill);
    // 2, 3-р банд — голдоо хаалганы зайтай
    canvas.drawRRect(bar(0.13, 0.66, 0.42, 0.75), fill);
    canvas.drawRRect(bar(0.58, 0.66, 0.87, 0.75), fill);
    canvas.drawRRect(bar(0.13, 0.77, 0.42, 0.86), fill);
    canvas.drawRRect(bar(0.58, 0.77, 0.87, 0.86), fill);

    // ── Улзий хээ (хаалганы оронд төв чимэг) — ромб ──
    final knot = Path()
      ..moveTo(w * 0.50, h * 0.655)
      ..lineTo(w * 0.585, h * 0.755)
      ..lineTo(w * 0.50, h * 0.855)
      ..lineTo(w * 0.415, h * 0.755)
      ..close();
    canvas.drawPath(knot, fill);

    // ── Утаа (тооноос дээш мушгиа) ──
    final smoke = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final smokePath = Path()
      ..moveTo(w * 0.52, h * 0.28)
      ..cubicTo(w * 0.40, h * 0.20, w * 0.64, h * 0.14, w * 0.50, h * 0.06);
    canvas.drawPath(smokePath, smoke);
  }

  @override
  bool shouldRepaint(_GerPainter old) => old.colors != colors;
}
