import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Мэдэгдлийн icon — неон гэр, хаалганд нь хонх.
/// Үндсэн дүрс нь бэлэн зураг ([_asset]); мэдэгдэл ирсэн үед код дээрээс
/// гэрлийн туяа + гэрэлтэлт нэмэгддэг (тоо нь дуудагч талд — badge).
///
/// [ringing] = true үед туяа анивчиж, гэр бага зэрэг "амьсгална".
/// Анимац хэрэгтэй бол [AnimatedGerIcon] ашигла.
class GerIcon extends StatelessWidget {
  static const String _asset = 'assets/icons/ger_bell.png';

  final double size;

  /// Туяаны өнгө (сүүлийн өнгийг ашиглана). Брэнд солигдвол энд дамжуулна.
  final List<Color> colors;

  /// Мэдэгдэл ирсэн эсэх.
  final bool ringing;

  /// Анимацийн фаз (0..1). [AnimatedGerIcon] дамжуулна.
  final double phase;

  const GerIcon({
    super.key,
    this.size = 26,
    this.colors = const [
      AppColors.accentStart, AppColors.accentMid, AppColors.accentEnd,
    ],
    this.ringing = false,
    this.phase = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Хонх дуугарахад гэр зөөлөн томорч-жижигрэнэ (2% — мэдрэгдэх ч анзаарагдахгүй)
    final pulse = ringing ? 1 + 0.025 * math.sin(phase * math.pi * 2) : 1.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: pulse,
            child: Image.asset(
              _asset,
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
              // Зураг ачаалагдаагүй агшинд байрлал үсрэхээс сэргийлнэ
              gaplessPlayback: true,
            ),
          ),
          if (ringing)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SparkPainter(colors.last, phase),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Мэдэгдэл ирсэн үед өөрөө анивчдаг хувилбар.
/// [ringing] false бол анимац зогсоно (батерей хэмнэнэ).
class AnimatedGerIcon extends StatefulWidget {
  final double size;
  final List<Color> colors;
  final bool ringing;

  const AnimatedGerIcon({
    super.key,
    this.size = 26,
    this.colors = const [
      AppColors.accentStart, AppColors.accentMid, AppColors.accentEnd,
    ],
    this.ringing = false,
  });

  @override
  State<AnimatedGerIcon> createState() => _AnimatedGerIconState();
}

class _AnimatedGerIconState extends State<AnimatedGerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.ringing) _c.repeat();
  }

  @override
  void didUpdateWidget(AnimatedGerIcon old) {
    super.didUpdateWidget(old);
    if (widget.ringing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.ringing && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => GerIcon(
          size: widget.size,
          colors: widget.colors,
          ringing: widget.ringing,
          phase: _c.value,
        ),
      );
}

/// Дээвэр дээрх гэрлийн туяа — зургийн геометрт тааруулсан байрлал.
class _SparkPainter extends CustomPainter {
  final Color color;
  final double phase;

  _SparkPainter(this.color, this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final blink = (0.5 + 0.5 * math.sin(phase * math.pi * 2)).clamp(0.0, 1.0);

    // Цайвар ягаан — зурган дээрх хонхны өнгөтэй нийцнэ
    final tint = Color.lerp(color, Colors.white, 0.6)!;

    final ray = Paint()
      ..color = tint.withValues(alpha: 0.35 + 0.65 * blink)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final glow = Paint()
      ..color = tint.withValues(alpha: 0.30 * blink)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03)
      ..isAntiAlias = true;

    void spark(double x1, double y1, double x2, double y2) {
      final a = Offset(w * x1, h * y1), b = Offset(w * x2, h * y2);
      canvas.drawLine(a, b, glow);
      canvas.drawLine(a, b, ray);
    }

    // зүүн тал
    spark(0.352, 0.232, 0.312, 0.168);
    spark(0.302, 0.288, 0.240, 0.252);
    // баруун тал
    spark(0.648, 0.232, 0.688, 0.168);
    spark(0.698, 0.288, 0.760, 0.252);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.phase != phase || old.color != color;
}
