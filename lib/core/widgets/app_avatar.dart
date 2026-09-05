import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// User avatar widget — matches JSX Avatar component
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? initial;
  final double size;
  final bool showRing;       // gradient ring
  final bool showOnlineDot;

  const AppAvatar({
    super.key,
    this.imageUrl,
    this.initial,
    this.size = 40,
    this.showRing = false,
    this.showOnlineDot = false,
  });

  @override
  Widget build(BuildContext context) {
    // Ring горимд: 2px sweep ring + 1.5px суурь өнгийн завсар (люкс төрх)
    final avatarSize = showRing ? size - 7 : size;

    Widget avatar;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: avatarSize,
          height: avatarSize,
          fit: BoxFit.cover,
          // Аватар жижиг тул decode-ыг 3x хэмжээгээр хязгаарлана (хурд + RAM)
          memCacheWidth: (avatarSize * 3).round(),
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, __) => _placeholder(avatarSize),
          errorWidget: (_, __, ___) => _placeholder(avatarSize),
        ),
      );
    } else {
      avatar = _placeholder(avatarSize);
    }

    if (showRing) {
      // Story ring — magenta → pink → cyan sweep + суурь өнгийн нарийн завсар
      avatar = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.storyRingGradient,
        ),
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.dynBgBase,
          ),
          padding: const EdgeInsets.all(1.5),
          child: avatar,
        ),
      );
    }

    if (showOnlineDot) {
      avatar = Stack(
        children: [
          avatar,
          Positioned(
            right: 0, bottom: 0,
            child: Container(
              width: size * 0.27,
              height: size * 0.27,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                // Хүрээ нь идэвхтэй theme-ийн суурьтай нийлнэ (light дээр цайвар)
                border: Border.all(color: AppColors.dynBgBase, width: 1.5),
                // Online — lime неон гэрэлтэлт
                boxShadow: [
                  BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.55),
                      blurRadius: 8, spreadRadius: 0.5),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(width: size, height: size, child: avatar);
  }

  Widget _placeholder(double sz) {
    return Container(
      width: sz, height: sz,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradientSoft,
      ),
      alignment: Alignment.center,
      child: Text(
        (initial ?? '?').toUpperCase(),
        style: AppTextStyles.labelLg.copyWith(
          fontSize: sz * 0.38,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
