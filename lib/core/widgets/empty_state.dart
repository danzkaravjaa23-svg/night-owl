import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Nightscape хоосон төлвийн нэгдсэн widget — template хэлбэр.
/// neon illustration (SVG) → glass medallion 96 (glow-г энд өгнө,
/// учир нь flutter_svg филтер дэмждэггүй) + h3 гарчиг + төвлөрсөн дэд + CTA pill.
/// Зай: medallion→24→гарчиг→8→дэд→24→action.
class EmptyState extends StatelessWidget {
  final String illustration; // assets/images/illustrations/*.svg
  final String title;
  final String? subtitle;
  final Widget? action;
  final double size;
  final Color glow;

  const EmptyState({
    super.key,
    required this.illustration,
    required this.title,
    this.subtitle,
    this.action,
    this.size = 96,
    this.glow = AppColors.neonCyan,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          // Зөөлөн fade + дээшлэх орох хөдөлгөөн — спиннерийн дараа
          // "гэнэт гарч ирэх" биш, амьсгалтай мэдрэмж өгнө
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                  offset: Offset(0, 12 * (1 - t)), child: child),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Glass medallion — bgElevated 0.72 + hairline + неон glow ──
            Container(
              width: size,
              height: size,
              padding: EdgeInsets.all(size * 0.13),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.dynBgElevated.withValues(alpha: 0.72),
                border: Border.all(color: AppColors.dynHairline2),
                // Зөөлөн неон гэрэлтэлт — glow өнгө + magenta давхарга
                boxShadow: [
                  BoxShadow(
                      color: glow.withValues(alpha: 0.22),
                      blurRadius: 34, spreadRadius: -4),
                  BoxShadow(
                      color: AppColors.accentStart.withValues(alpha: 0.10),
                      blurRadius: 40, spreadRadius: -12),
                ],
              ),
              child: SvgPicture.asset(illustration),
            ),
            const SizedBox(height: 24),
            Text(title, style: AppTextStyles.h3, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              // Урт текст хэт сунахгүй — уншихад эвтэйхэн өргөнд барина
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(subtitle!,
                    style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.dynTextSecondary, height: 1.5),
                    textAlign: TextAlign.center),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
            ]),
          ),
        ),
      );
}
