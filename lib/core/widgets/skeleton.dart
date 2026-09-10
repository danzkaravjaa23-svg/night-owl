import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';

/// Ачаалалтын "араг яс" (skeleton) хэсгийг нэг хэмнэлээр анивчуулна.
/// (Өмнө нь 12 хувийн класс 0.4–0.9 / 0.45–1.0 гэсэн өөр хүрээ,
/// өөр хугацаатай анивчдаг байсныг нэгтгэв.)
///
/// Хэрэглэгч хөдөлгөөн багасгах тохиргоо асаасан бол анивчихгүй —
/// зөвхөн 0.7 тунгалагаар харуулна.
class SkeletonPulse extends StatefulWidget {
  final Widget child;

  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.45,
    upperBound: 1.0,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Хүртээмж: хөдөлгөөн унтраасан үед анивчилтгүй, тогтмол бүдэг.
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_c.isAnimating) _c.stop();
      return Opacity(opacity: 0.7, child: widget.child);
    }
    if (!_c.isAnimating) _c.repeat(reverse: true);
    return FadeTransition(opacity: _c, child: widget.child);
  }
}

/// Skeleton-ы үндсэн тоосго — bgSurface дүүргэлттэй тэгш өнцөгт.
/// Өргөн/өндөр өгөөгүй бол эцэг нь хэмжээг тодорхойлно.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadii.sm,
  });

  @override
  Widget build(BuildContext context) => SkeletonPulse(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.dynBgSurface,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}
