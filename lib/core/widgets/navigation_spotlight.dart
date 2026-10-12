import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_motion.dart';

/// A single pool of light follows the selected destination, then stays still.
/// The entire effect is decorative; navigation controls remain above it.
class NavigationSpotlight extends StatelessWidget {
  final int selectedIndex;
  final int itemCount;

  const NavigationSpotlight({
    super.key,
    required this.selectedIndex,
    this.itemCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget light(double position) => CustomPaint(
          painter: _SpotlightPainter(
              position: position, itemCount: itemCount, dark: dark),
        );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AppMotion.reduced(context)
              ? light(selectedIndex.toDouble())
              : TweenAnimationBuilder<double>(
                  tween: Tween(
                      begin: selectedIndex.toDouble(),
                      end: selectedIndex.toDouble()),
                  duration: AppMotion.duration(
                      context, const Duration(milliseconds: 420)),
                  curve: Curves.easeOutCubic,
                  builder: (_, position, __) => light(position),
                ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final double position;
  final int itemCount;
  final bool dark;
  const _SpotlightPainter({
    required this.position,
    required this.itemCount,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final slot = size.width / itemCount;
    final x = slot * (position + .5);
    final emitterWidth = (slot * .38).clamp(20.0, 32.0);
    final bottom = size.height * .86;
    final violet = dark ? AppColors.silverNeon : AppColors.accentStart;
    final beam = Path()
      ..moveTo(x - emitterWidth / 2, 8.5)
      ..lineTo(x + emitterWidth / 2, 8.5)
      ..lineTo(x + slot * .48, bottom)
      ..quadraticBezierTo(x, bottom + 5, x - slot * .48, bottom)
      ..close();

    // The cone fades before reaching the label/dot; no animated blur layers.
    final beamBounds = Rect.fromLTWH(x - slot / 2, 8.5, slot, bottom - 8.5);
    canvas.drawPath(
      beam,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            violet.withValues(alpha: dark ? .32 : .19),
            AppColors.accentStart.withValues(alpha: dark ? .24 : .10),
            violet.withValues(alpha: dark ? .08 : .035),
            violet.withValues(alpha: 0),
          ],
          stops: const [0, .35, .72, 1],
        ).createShader(beamBounds),
    );

    final halo = Rect.fromCenter(
        center: Offset(x, size.height * .38),
        width: slot * .76,
        height: size.height * .72);
    canvas.drawOval(
      halo,
      Paint()
        ..shader = RadialGradient(colors: [
          violet.withValues(alpha: dark ? .18 : .07),
          violet.withValues(alpha: 0),
        ]).createShader(halo),
    );

    final source =
        Rect.fromCenter(center: Offset(x, 7), width: emitterWidth, height: 3.5);
    for (final spread in [6.0, 3.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            source.inflate(spread), const Radius.circular(9)),
        Paint()..color = violet.withValues(alpha: dark ? .075 : .04),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(source, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(colors: [
          AppColors.accentStart,
          dark ? AppColors.silverLight : AppColors.silverDark,
          AppColors.accentStart,
        ]).createShader(source),
    );

    final dot = Offset(x, size.height - 6);
    final dotHalo = Rect.fromCircle(center: dot, radius: 7);
    canvas.drawCircle(
      dot,
      7,
      Paint()
        ..shader = RadialGradient(colors: [
          violet.withValues(alpha: .34),
          violet.withValues(alpha: 0),
        ]).createShader(dotHalo),
    );
    canvas.drawCircle(dot, 2.3, Paint()..color = violet);
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      position != oldDelegate.position ||
      itemCount != oldDelegate.itemCount ||
      dark != oldDelegate.dark;
}
