import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'night_owl_brand.dart';

/// Өргөн дэлгэц (веб / таблет / desktop) дээр аппыг утасны өргөнөөр
/// голлуулж хязгаарлана — ингэснээр товч, зураг, текст сунахгүй,
/// яг утсан дээрхтэй ижил хэмжээтэй харагдана.
///
/// Утсан дээр (өргөн нь [breakpoint]-оос бага) юу ч өөрчлөхгүй —
/// child-аа шууд буцаана.
class MobileFrame extends StatelessWidget {
  final Widget child;
  final bool wideLayout;

  /// Энэ өргөнөөс дээш үед л хүрээ идэвхжинэ.
  final double breakpoint;

  /// Аппын харагдах өргөн (утасны логик өргөнтэй ойролцоо).
  final double maxWidth;

  const MobileFrame({
    super.key,
    required this.child,
    this.wideLayout = false,
    this.breakpoint = 520,
    this.maxWidth = 420,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= breakpoint) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final h = mq.size.height;
    final frameWidth = wideLayout && mq.size.width >= 900
        ? (mq.size.width - 48).clamp(420.0, 1120.0)
        : maxWidth;

    return Material(
      // Хажуугийн зай — аппын дэвсгэрээс бага зэрэг гүн, ингэснээр
      // голын багана "төхөөрөмж" мэт тодорхой хүрээтэй харагдана.
      color: isDark ? const Color(0xFF080A12) : const Color(0xFFEDEBF5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!wideLayout && mq.size.width >= 1000)
            const Expanded(child: _DesktopBrand()),
          Container(
            width: frameWidth,
            height: h,
            decoration: BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(
                  color: isDark ? AppColors.hairline : AppColors.hairlineLight,
                  width: 1,
                ),
              ),
            ),
            // MediaQuery-г хамт нарийсгана — эс бөгөөс дотоод дэлгэцүүд
            // цонхны бүтэн өргөнөөр тооцоолж, буруу байрлана.
            child: MediaQuery(
              data: mq.copyWith(size: Size(frameWidth, h)),
              child: ClipRect(child: child),
            ),
          ),
          if (!wideLayout && mq.size.width >= 1000) const Spacer(),
        ],
      ),
    );
  }
}

class _DesktopBrand extends StatelessWidget {
  const _DesktopBrand();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NightOwlMark(size: 78),
              const SizedBox(height: 24),
              Text('night owl',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 34,
                      letterSpacing: -1.4,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Text('Сайхан үдэш.\nХамтдаа.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 18,
                      height: 1.6)),
              const SizedBox(height: 36),
              Text('ULAANBAATAR / AFTER HOURS',
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      letterSpacing: 2)),
            ]),
      );
}
