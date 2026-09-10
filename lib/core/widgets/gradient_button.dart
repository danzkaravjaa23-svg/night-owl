import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Дарахад зөөлөн агшиж (spring press) премиум мэдрэмж өгөх wrapper —
/// Gradient/Outline хоёр товч хоёулаа ижил мэдрэмжтэй байхаар нэгтгэсэн.
class _PressScale extends StatefulWidget {
  final bool enabled;
  final Widget child;
  const _PressScale({required this.enabled, required this.child});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (widget.enabled) setState(() => _pressed = true);
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Gradient товчны хэмжээ: lg = 52px (үндсэн CTA), md = 40px (мөрөнд суух товч).
enum GradientButtonSize { lg, md }

/// Primary gradient button — CSS .ns-btn-primary
/// Дарахад зөөлөн агшиж (spring press) премиум мэдрэмж өгнө.
/// busy=true үед label-ийн оронд спиннер гарч, товч түр идэвхгүй болно.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Widget? trailing;
  /// Тодорхой өндөр өгвөл [size]-аас давуу.
  final double? height;
  final double borderRadius;
  final bool busy;
  final GradientButtonSize size;
  /// false бол агуулгынхаа өргөнөөр (мөрөнд зэрэгцүүлэхэд).
  final bool fullWidth;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailing,
    this.height,
    this.borderRadius = 14,
    this.busy = false,
    this.size = GradientButtonSize.lg,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final md = size == GradientButtonSize.md;
    final h = height ?? (md ? 40.0 : 52.0);
    final labelStyle = md ? AppTextStyles.btnSm : AppTextStyles.btn;
    // busy үед gradient хэвээр (ажиллаж буй мэдрэмж), зөвхөн disabled үед бүдгэрнэ
    final disabled = onPressed == null;
    final effective = (busy || disabled) ? null : onPressed;
    return _PressScale(
      enabled: effective != null,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        height: h,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: !disabled
                ? AppColors.accentGradient
                : LinearGradient(colors: [
                    AppColors.dynBgSurface, AppColors.dynBgSurface]),
            borderRadius: BorderRadius.circular(borderRadius),
            // Шилэн ирмэг — дээд гэрлийн нарийн hairline
            border: Border.all(
                color: !disabled
                    ? Colors.white.withValues(alpha: 0.14)
                    : AppColors.dynHairline),
            // Неон glow — magenta ойрын + pink холын давхар сүүдэр
            boxShadow: !disabled
                ? [
                    BoxShadow(
                      color: AppColors.accentStart
                          .withValues(alpha: busy ? 0.22 : 0.35),
                      blurRadius: 22, spreadRadius: -2,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: AppColors.accentEnd
                          .withValues(alpha: busy ? 0.14 : 0.22),
                      blurRadius: 32, spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: ElevatedButton(
            onPressed: effective,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              // busy үед onPressed=null дамждаг тул M3-ийн disabled саарал
              // gradient-ийг дардаг байв — үндсэн CTA хүлээж байхдаа
              // идэвхгүй мэт харагдана. Тунгалаг болгож gradient-ийг хэвээр үлдээв.
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: Colors.white,
              shadowColor: Colors.transparent,
              minimumSize: Size(fullWidth ? double.infinity : 0, h),
              padding: md
                  ? const EdgeInsets.symmetric(horizontal: 20)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
            // Спиннер ↔ label солигдоход зөөлөн fade + scale шилжилт
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                    child: child),
              ),
              child: busy
                  ? SizedBox(
                      key: const ValueKey('busy'),
                      width: md ? 18 : 22, height: md ? 18 : 22,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Row(
                      key: const ValueKey('label'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[icon!, const SizedBox(width: 8)],
                        Text(label,
                            style: !disabled
                                ? labelStyle
                                // Идэвхгүй товч бүдэг label-тай — disabled гэдэг нь илт
                                : labelStyle.copyWith(
                                    color: AppColors.dynTextTertiary)),
                        if (trailing != null) ...[
                          const SizedBox(width: 8), trailing!],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary outline button — CSS .ns-btn-secondary
class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double height;

  const OutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      enabled: onPressed != null,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.dynBgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.dynHairline2),
          ),
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.dynTextPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 8)],
                Text(label, style: AppTextStyles.btn.copyWith(
                  fontWeight: FontWeight.w600,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
