import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Вэб бус платформын fallback (одоо зөвхөн web дээр ажиллаж байгаа).
class VideoView extends StatelessWidget {
  final String url;
  final bool posterOnly;
  final double? height;
  final bool autoplay;
  final bool showPosterIcon;
  final bool active;
  final ValueNotifier<double>? progress;

  /// Веб хувилбартай ижил гарын үсэг — native контрол харуулах эсэх
  /// (энэ fallback дээр жинхэнэ плейер байхгүй тул зөвхөн API-гийн нэгдэл).
  final bool showControls;

  const VideoView({
    super.key,
    required this.url,
    this.posterOnly = false,
    this.height,
    this.autoplay = false,
    this.showPosterIcon = true,
    this.active = true,
    this.progress,
    this.showControls = false,
  });

  @override
  Widget build(BuildContext context) {
    final mediaHeight = posterOnly ? 220.0 : (height ?? 360.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: posterOnly ? null : mediaHeight,
        constraints: posterOnly ? const BoxConstraints(minHeight: 220) : null,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.bgElevated,
              AppColors.bgSurface,
            ],
          ),
          border: Border.all(color: AppColors.hairline),
          boxShadow: AppColors.shadowCard,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradientSoft,
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.58),
                      Colors.black.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    if (showPosterIcon || active)
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.accentGradient,
                            boxShadow: AppColors.glowShadow(
                              AppColors.accentStart,
                              alpha: 0.38,
                              blur: 24,
                            ),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (active)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          autoplay ? 'LIVE' : 'VIDEO',
                          style: AppTextStyles.labelSm.copyWith(
                            color: AppColors.success,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: progress!,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.neonCyan,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
