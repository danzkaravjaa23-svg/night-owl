import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_motion.dart';

enum OwlLoadingState { loading, success, error }

enum OwlMood { curious, wink, happy, patient }

/// Auxiliary owl emotion with an isolated blink/float while real work runs.
/// Terminal states and reduced-motion/offstage views never keep a ticker alive.
class OwlLoading extends StatefulWidget {
  final String? message;
  final String? detail;
  final double size;
  final bool compact;
  final bool onDark;
  final OwlLoadingState state;
  final VoidCallback? onRetry;

  const OwlLoading({
    super.key,
    this.message,
    this.detail,
    this.size = 56,
    this.compact = false,
    this.onDark = false,
    this.state = OwlLoadingState.loading,
    this.onRetry,
  });

  @override
  State<OwlLoading> createState() => _OwlLoadingState();
}

class _OwlLoadingState extends State<OwlLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
    animationBehavior: AnimationBehavior.preserve,
  );

  void _syncAnimation() {
    final animate = widget.state == OwlLoadingState.loading &&
        !AppMotion.reduced(context) &&
        TickerMode.of(context);
    if (animate) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
      _phase.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(OwlLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  String get _message =>
      widget.message ??
      switch (widget.state) {
        OwlLoadingState.loading => 'Ачаалж байна',
        OwlLoadingState.success => 'Амжилттай',
        OwlLoadingState.error => 'Ачаалж чадсангүй',
      };

  @override
  Widget build(BuildContext context) {
    final color = widget.onDark ? Colors.white : AppColors.textSecondary;
    final mark = RepaintBoundary(
      child: SizedBox(
        width: widget.size + (widget.compact ? 0 : 8),
        height: widget.size + (widget.compact ? 0 : 8),
        child: Center(
          child: AnimatedBuilder(
            animation: _phase,
            builder: (_, __) => Transform.translate(
              offset: Offset(
                  0,
                  -math.sin(_phase.value * 2 * math.pi) *
                      math.min(2.5, widget.size * .035)),
              child: OwlEmotion(
                size: widget.size,
                mood: switch (widget.state) {
                  OwlLoadingState.loading =>
                    _phase.value >= .78 && _phase.value <= .86
                        ? OwlMood.wink
                        : OwlMood.curious,
                  OwlLoadingState.success => OwlMood.happy,
                  OwlLoadingState.error => OwlMood.patient,
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.compact) {
      return Semantics(label: _message, child: ExcludeSemantics(child: mark));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label:
              widget.detail == null ? _message : '$_message. ${widget.detail}',
          liveRegion: true,
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              if (widget.state == OwlLoadingState.loading) ...[
                const SizedBox(height: 8),
                RepaintBoundary(
                  child: CustomPaint(
                    size: const Size(36, 6),
                    painter: _ScanDotsPainter(_phase, color),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.exit),
                child: Text(
                  _message,
                  key: ValueKey(_message),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4),
                ),
              ),
              if (widget.detail != null) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(widget.detail!,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, height: 1.45, color: color)),
                ),
              ],
            ],
          ),
        ),
        if (widget.state == OwlLoadingState.error && widget.onRetry != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PressFeedback(
                child: TextButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Дахин оролдох'),
            )),
          ),
      ],
    );
  }
}

/// Runtime quadrant selection from the auxiliary Higgsfield emotion atlas.
/// Header/master logos continue using NightOwlMark.
class OwlEmotion extends StatelessWidget {
  final OwlMood mood;
  final double size;
  const OwlEmotion({super.key, this.mood = OwlMood.curious, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
    final alignment = switch (mood) {
      OwlMood.curious => Alignment.topLeft,
      OwlMood.wink => Alignment.topRight,
      OwlMood.happy => Alignment.bottomLeft,
      OwlMood.patient => Alignment.bottomRight,
    };
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          minWidth: size * 2,
          maxWidth: size * 2,
          minHeight: size * 2,
          maxHeight: size * 2,
          alignment: alignment,
          child: Image.asset(
            'assets/images/owl_emotions.png',
            width: size * 2,
            height: size * 2,
            cacheWidth: (size * 2 * pixelRatio).ceil().clamp(64, 512),
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

class _ScanDotsPainter extends CustomPainter {
  final Animation<double> phase;
  final Color color;
  _ScanDotsPainter(this.phase, this.color) : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final strength = (math.sin(phase.value * 4 * math.pi - i * 1.2) + 1) / 2;
      canvas.drawCircle(Offset(6 + i * 12.0, 3), 2.2,
          Paint()..color = color.withValues(alpha: .25 + strength * .60));
    }
  }

  @override
  bool shouldRepaint(_ScanDotsPainter old) =>
      old.color != color || old.phase != phase;
}
