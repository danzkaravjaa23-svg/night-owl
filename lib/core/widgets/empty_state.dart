import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_motion.dart';

/// Nightscape хоосон төлвийн нэгдсэн widget — template хэлбэр.
/// neon illustration (SVG) → glass medallion 96 (glow-г энд өгнө,
/// учир нь flutter_svg филтер дэмждэггүй) + h3 гарчиг + төвлөрсөн дэд + CTA pill.
/// Зай: medallion→24→гарчиг→8→дэд→24→action.
class EmptyState extends StatelessWidget {
  final String? illustration; // assets/images/illustrations/*.svg
  /// SVG зурагтай биш үед — медальон дотор icon (32px) харуулна.
  /// [illustration] эсвэл [icon]-ын нэг нь заавал байх ёстой.
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final double size;

  /// null бол [AppColors.neonCyan] (горимд тохирсон адаптив өнгө).
  final Color? glow;

  const EmptyState({
    super.key,
    this.illustration,
    this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.size = 96,
    this.glow,
  }) : assert(icon != null || illustration != null,
            'EmptyState-д illustration эсвэл icon-ын аль нэгийг өгнө үү');

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.hasBoundedHeight && constraints.maxHeight < 360;
          final markSize = compact ? size.clamp(40.0, 64.0) : size;
          final content = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 24, vertical: compact ? 20 : 32),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: AppMotion.duration(context, AppMotion.enter),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                        offset: Offset(0, 8 * (1 - t)), child: child),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ExcludeSemantics(
                      child: Container(
                        width: markSize,
                        height: markSize,
                        padding: EdgeInsets.all(markSize * .15),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.dynBgElevated,
                              AppColors.dynBgSurface
                            ],
                          ),
                          border: Border.all(color: AppColors.dynHairline2),
                          boxShadow: [
                            BoxShadow(
                                color: (glow ?? AppColors.neonCyan)
                                    .withValues(alpha: .12),
                                blurRadius: 28,
                                spreadRadius: -6),
                          ],
                        ),
                        child: illustration != null
                            ? SvgPicture.asset(illustration!)
                            : Center(
                                child: Icon(icon,
                                    size: 30,
                                    color: glow ?? AppColors.neonCyan)),
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 24),
                    Semantics(
                      header: true,
                      child: Text(title,
                          style: AppTextStyles.h3
                              .copyWith(fontSize: 17, height: 1.35),
                          textAlign: TextAlign.center),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(subtitle!,
                          style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.dynTextSecondary, height: 1.5),
                          textAlign: TextAlign.center),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: 24),
                      action!
                    ],
                  ]),
                ),
              ),
            ),
          );
          // Keyboard and large text can leave very little vertical room. Keep
          // recovery actions reachable instead of clipping the empty state.
          if (!constraints.hasBoundedHeight) return content;
          return SingleChildScrollView(
            primary: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: content,
            ),
          );
        },
      );
}
