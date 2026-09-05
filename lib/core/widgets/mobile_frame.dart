import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Өргөн дэлгэц (веб / таблет / desktop) дээр аппыг утасны өргөнөөр
/// голлуулж хязгаарлана — ингэснээр товч, зураг, текст сунахгүй,
/// яг утсан дээрхтэй ижил хэмжээтэй харагдана.
///
/// Утсан дээр (өргөн нь [breakpoint]-оос бага) юу ч өөрчлөхгүй —
/// child-аа шууд буцаана.
class MobileFrame extends StatelessWidget {
  final Widget child;

  /// Энэ өргөнөөс дээш үед л хүрээ идэвхжинэ.
  final double breakpoint;

  /// Аппын харагдах өргөн (утасны логик өргөнтэй ойролцоо).
  final double maxWidth;

  const MobileFrame({
    super.key,
    required this.child,
    this.breakpoint = 520,
    this.maxWidth = 420,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= breakpoint) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final h = mq.size.height;

    return ColoredBox(
      // Хажуугийн зай — аппын дэвсгэрээс бага зэрэг гүн, ингэснээр
      // голын багана "төхөөрөмж" мэт тодорхой хүрээтэй харагдана.
      color: isDark ? const Color(0xFF000000) : const Color(0xFFEDE7DC),
      child: Center(
        child: Container(
          width: maxWidth,
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
            data: mq.copyWith(size: Size(maxWidth, h)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
