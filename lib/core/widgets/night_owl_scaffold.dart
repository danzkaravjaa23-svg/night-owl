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
      backgroundColor: backgroundColor ?? AppColors.bgBase,
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
    // Top-left purple glow
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accentPurple.withOpacity(0.12),
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

    // Bottom-right pink glow
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accentStart.withOpacity(0.10),
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
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Phone status bar (time + icons) — matches PhoneStatus JSX
class PhoneStatusBar extends StatelessWidget implements PreferredSizeWidget {
  const PhoneStatusBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _currentTime(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            Row(
              children: const [
                Icon(Icons.signal_cellular_alt, size: 16, color: AppColors.textPrimary),
                SizedBox(width: 6),
                Icon(Icons.wifi, size: 16, color: AppColors.textPrimary),
                SizedBox(width: 6),
                Icon(Icons.battery_full, size: 16, color: AppColors.textPrimary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _currentTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
