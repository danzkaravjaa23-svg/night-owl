import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Nightscape хоосон төлвийн нэгдсэн widget.
/// neon illustration (SVG) → glass medallion дотор (glow-г энд өгнө,
/// учир нь flutter_svg филтер дэмждэггүй) + гарчиг + дэд + (CTA).
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
    this.size = 132,
    this.glow = AppColors.neonCyan,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: size,
              height: size,
              padding: EdgeInsets.all(size * 0.13),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgElevated.withValues(alpha: 0.40),
                border: Border.all(color: AppColors.hairline2),
                boxShadow: [
                  BoxShadow(
                      color: glow.withValues(alpha: 0.18),
                      blurRadius: 30, spreadRadius: -6),
                  BoxShadow(
                      color: AppColors.accentStart.withValues(alpha: 0.12),
                      blurRadius: 34, spreadRadius: -10),
                ],
              ),
              child: SvgPicture.asset(illustration),
            ),
            const SizedBox(height: 22),
            Text(title, style: AppTextStyles.h1, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textSecondary, height: 1.5),
                  textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ]),
        ),
      );
}
