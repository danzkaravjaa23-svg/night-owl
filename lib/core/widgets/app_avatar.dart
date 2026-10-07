import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants/avatar_presets.dart';
import '../theme/app_colors.dart';

/// Uploaded photos and built-in owl portraits share one renderer everywhere.
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  // Retained for existing call sites; photo-less users now receive an owl.
  final String? initial;
  final double size;
  final bool showRing; // gradient ring
  final bool showOnlineDot;

  /// Үргэлж харанхуй гадаргуу (story, reels, live) дээр — гэрэл горимд ч
  /// цагирагны завсар болон хүрээ харанхуй палитраар зурагдана.
  final bool onDark;

  const AppAvatar({
    super.key,
    this.imageUrl,
    this.initial,
    this.size = 40,
    this.showRing = false,
    this.showOnlineDot = false,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    // Ring горимд: 2px sweep ring + 1.5px суурь өнгийн завсар (люкс төрх)
    final avatarSize = showRing ? size - 7 : size;

    Widget avatar;
    final preset = NightOwlAvatars.fromValue(imageUrl);
    if (preset != null) {
      avatar = _presetAvatar(avatarSize, preset);
    } else if (NightOwlAvatars.isNetworkPhoto(imageUrl)) {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl!.trim(),
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
            color: onDark ? AppColors.bgBaseDark : AppColors.bgBase,
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
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.27,
              height: size * 0.27,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                // Хүрээ нь идэвхтэй theme-ийн суурьтай нийлнэ (light дээр цайвар)
                border: Border.all(
                    color: onDark ? AppColors.bgBaseDark : AppColors.bgBase,
                    width: 1.5),
                // Online — lime неон гэрэлтэлт
                boxShadow: [
                  BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 0.5),
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
    return _presetAvatar(sz, NightOwlAvatars.defaultPreset);
  }

  Widget _presetAvatar(double sz, NightOwlAvatarPreset preset) => ClipOval(
        child: Image.asset(preset.assetPath,
            width: sz,
            height: sz,
            fit: BoxFit.cover,
            cacheWidth: (sz * 3).round().clamp(1, 512),
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => Image.asset(
                'assets/icons/night_owl_mark.png',
                width: sz,
                height: sz,
                fit: BoxFit.contain,
                excludeFromSemantics: true)),
      );
}
