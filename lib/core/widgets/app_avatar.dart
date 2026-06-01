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
    final avatarSize = showRing ? size - 4 : size;

    Widget avatar;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: avatarSize,
          height: avatarSize,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(avatarSize),
          errorWidget: (_, __, ___) => _placeholder(avatarSize),
        ),
      );
    } else {
      avatar = _placeholder(avatarSize);
    }

    if (showRing) {
      avatar = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentGradient,
        ),
        padding: const EdgeInsets.all(2),
        child: avatar,
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
                border: Border.all(color: AppColors.bgBase, width: 1.5),
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
