import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'sculpted_icon.dart';
import 'app_motion.dart';
import 'owl_loading.dart';

Widget _dimensionalButtonIcon(Widget child, {bool primary = false}) {
  if (child is Icon && child.icon != null) {
    return SculptedIcon(child.icon!,
        size: child.size ?? 20,
        color: primary ? Colors.white : child.color,
        onDark: primary);
  }
  return child;
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

  /// Хамгийн бага өндөр. Том бичвэртэй үед агуулгадаа тохирч өснө.
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
    // Magenta gradient дээрх label — горимоос үл хамааран цагаан (харанхуй
    // горимын textPrimary-тай яг ижил утга тул dark горимд өөрчлөлтгүй).
    final labelStyle = (md ? AppTextStyles.btnSm : AppTextStyles.btn)
        .copyWith(color: AppColors.textPrimaryDark);
    // busy үед gradient хэвээр (ажиллаж буй мэдрэмж), зөвхөн disabled үед бүдгэрнэ
    final disabled = onPressed == null;
    final effective = (busy || disabled) ? null : onPressed;
    return PressFeedback(
      enabled: effective != null,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        child: AnimatedContainer(
          constraints: BoxConstraints(minHeight: h),
          duration: AppMotion.duration(context, AppMotion.exit),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: !disabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                        Color(0xFF8661DC),
                        Color(0xFF7654D6),
                        Color(0xFF5D3AAB)
                      ])
                : LinearGradient(
                    colors: [AppColors.dynBgSurface, AppColors.dynBgSurface]),
            borderRadius: BorderRadius.circular(borderRadius),
            // Шилэн ирмэг — дээд гэрлийн нарийн hairline
            border: Border.all(
                color: !disabled
                    ? Colors.white.withValues(alpha: 0.14)
                    : AppColors.dynHairline),
            // Неон glow — magenta ойрын + pink холын давхар сүүдэр
            boxShadow: !disabled
                ? [
                    const BoxShadow(
                        color: Color(0xFF49307B),
                        offset: Offset(0, 3),
                        blurRadius: 0),
                    BoxShadow(
                      color: AppColors.accentStart
                          .withValues(alpha: busy ? 0.10 : 0.16),
                      blurRadius: 22,
                      spreadRadius: -2,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: AppColors.accentEnd
                          .withValues(alpha: busy ? 0.06 : 0.08),
                      blurRadius: 32,
                      spreadRadius: 0,
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
              padding:
                  EdgeInsets.symmetric(horizontal: md ? 16 : 20, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
            // Спиннер ↔ label солигдоход зөөлөн fade + scale шилжилт
            child: AnimatedSwitcher(
              duration: AppMotion.duration(context, AppMotion.exit),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                    scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                    child: child),
              ),
              child: busy
                  ? OwlLoading(
                      key: const ValueKey('busy'),
                      size: md ? 18 : 24,
                      compact: true,
                      onDark: true,
                      message: '$label: түр хүлээнэ үү')
                  : Row(
                      key: const ValueKey('label'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          _dimensionalButtonIcon(icon!, primary: true),
                          const SizedBox(width: 8)
                        ],
                        Flexible(
                            child: Text(label,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: !disabled
                                    ? labelStyle
                                    // Идэвхгүй товч бүдэг label-тай — disabled гэдэг нь илт
                                    : labelStyle.copyWith(
                                        color: AppColors.dynTextTertiary))),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!
                        ],
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
    return PressFeedback(
      enabled: onPressed != null,
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.bgElevated, AppColors.bgSurface]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.dynHairline2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black
                      .withValues(alpha: AppColors.isDarkMode ? .16 : .06),
                  offset: const Offset(0, 3),
                  blurRadius: 6)
            ],
          ),
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              minimumSize: Size(double.infinity, height),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              foregroundColor: AppColors.dynTextPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  _dimensionalButtonIcon(icon!),
                  const SizedBox(width: 8)
                ],
                Flexible(
                    child: Text(label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.btn.copyWith(
                          fontWeight: FontWeight.w600,
                        ))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
