import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Base scaffold with NightOwl aurora background
/// Бүх дэлгэцийн суурь layout
class NightOwlScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool extendBehindAppBar;
  final bool showAurora;
  final Color? backgroundColor;

  const NightOwlScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.extendBehindAppBar = false,
    this.showAurora = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Theme-ээс уншина — Dark горимд bgBase хэвээр, Light горимд цайвар суурь
      backgroundColor:
          backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: extendBehindAppBar,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          if (showAurora) _AuroraBackground(),
          body,
        ],
      ),
    );
  }
}

class _AuroraBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _AuroraPainter()),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Зүүн дээд — magenta неон уур
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accentStart.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.2, size.height * 0.2),
        radius: size.width * 0.5,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.2),
      size.width * 0.5,
      paint1,
    );

    // Баруун доод — cyan неон уур
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.neonCyan.withValues(alpha: 0.07),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.8, size.height * 0.8),
        radius: size.width * 0.5,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.8),
      size.width * 0.5,
      paint2,
    );

    // Доод төв — magenta spotlight: хөвөгч док болон FAB-ийн ард
    // гүн мэдрэмж өгөх статик гэрэл (blur биш — web perf аюулгүй)
    final paint3 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accentStart.withValues(alpha: 0.09),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.5, size.height * 1.05),
        radius: size.width * 0.55,
      ));
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 1.05),
      size.width * 0.55,
      paint3,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
