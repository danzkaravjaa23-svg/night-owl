import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_motion.dart';

/// A stationary pool of violet light. No blur layers or perpetual tickers.
class NightOwlAtmosphere extends StatelessWidget {
  final Widget child;
  const NightOwlAtmosphere({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-.85, -1),
            radius: 1.5,
            colors: [
              AppColors.accentStart
                  .withValues(alpha: AppColors.isDarkMode ? .19 : .08),
              AppColors.bgBase.withValues(alpha: 0),
            ],
          ),
        ),
        child: child,
      );
}

/// Shared satin surfaces, with a light-catching rim and soft depth.
abstract class PremiumSurface {
  static BoxDecoration card({double radius = 24}) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.isDarkMode
              ? const [Color(0xFF201E35), Color(0xFF111522)]
              : const [Color(0xFFFFFFFF), Color(0xFFF1EDF9)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
            color: AppColors.silver
                .withValues(alpha: AppColors.isDarkMode ? .18 : .14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: AppColors.isDarkMode ? .19 : .045),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      );
}

/// One light sweep on hover, focus or press, painted independently of content.
/// It never starts a timer or rebuilds the wrapped button on animation frames.
class ActionSheen extends StatefulWidget {
  final Widget child;
  final double radius;
  final bool enabled;
  const ActionSheen({
    super.key,
    required this.child,
    this.radius = 16,
    this.enabled = true,
  });

  @override
  State<ActionSheen> createState() => _ActionSheenState();
}

class _ActionSheenState extends State<ActionSheen>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 640));

  void _sweep() {
    if (widget.enabled &&
        !AppMotion.reduced(context) &&
        TickerMode.of(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) || !TickerMode.of(context)) {
      _controller.reset();
    }
  }

  @override
  void didUpdateWidget(ActionSheen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _controller.reset();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => _sweep(),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (focused) {
            if (focused) _sweep();
          },
          child: Listener(
            onPointerDown: (_) => _sweep(),
            child: Stack(children: [
              widget.child,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.radius),
                    child: CustomPaint(painter: _SheenPainter(_controller)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _SheenPainter extends CustomPainter {
  final Animation<double> progress;
  _SheenPainter(this.progress) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress.value <= 0 || progress.value >= 1) return;
    final width = size.width * .42;
    final x = -width + (size.width + width * 2) * progress.value;
    final rect = Rect.fromLTWH(x, 0, width, size.height);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(colors: [
            Colors.transparent,
            Color(0x30FFFFFF),
            Colors.transparent,
          ]).createShader(rect));
  }

  @override
  bool shouldRepaint(_SheenPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
