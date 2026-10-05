import 'package:flutter/material.dart';

/// Short, bounded motion shared by controls and routes. Never animates blur.
abstract class AppMotion {
  static const press = Duration(milliseconds: 90);
  static const release = Duration(milliseconds: 240);
  static const enter = Duration(milliseconds: 280);
  static const exit = Duration(milliseconds: 200);

  static bool reduced(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
  }

  static Duration duration(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Paint-only press/hover response; activation stays with the wrapped control.
class PressFeedback extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double pressedScale;
  final bool hover;

  const PressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = .965,
    this.hover = true,
  });

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed && mounted) setState(() => _pressed = pressed);
  }

  @override
  void didUpdateWidget(PressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pressed = false;
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return MouseRegion(
      onEnter: widget.enabled && widget.hover
          ? (_) => setState(() => _hovered = true)
          : null,
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
        _setPressed(false);
      },
      child: Listener(
        onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: reduced || !widget.enabled
              ? 1
              : _pressed
                  ? widget.pressedScale
                  : _hovered
                      ? 1.015
                      : 1,
          duration: AppMotion.duration(
              context, _pressed ? AppMotion.press : AppMotion.release),
          curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}

enum AppTransitionStyle { fade, detail, sheet }

/// Uses the Navigator's existing animation without copying/rebuilding pages.
class AppRouteTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final AppTransitionStyle style;

  const AppRouteTransition({
    super.key,
    required this.animation,
    required this.child,
    this.style = AppTransitionStyle.fade,
  });

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, page) {
        final curve = animation.status == AnimationStatus.reverse
            ? Curves.easeInCubic
            : Curves.easeOutCubic;
        final progress = curve.transform(animation.value);
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final offset = switch (style) {
          AppTransitionStyle.fade => Offset(0, .015 * (1 - progress)),
          AppTransitionStyle.detail =>
            Offset((rtl ? -.045 : .045) * (1 - progress), 0),
          AppTransitionStyle.sheet => Offset(0, .065 * (1 - progress)),
        };
        return Opacity(
          opacity: progress,
          child: FractionalTranslation(
            translation: offset,
            child: page,
          ),
        );
      },
    );
  }
}

/// One entrance for small result/empty cards; its child stays cached per frame.
class AppEntrance extends StatelessWidget {
  final Widget child;
  const AppEntrance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.enter,
      curve: Curves.easeOutCubic,
      builder: (_, value, content) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)), child: content),
      ),
      child: child,
    );
  }
}
