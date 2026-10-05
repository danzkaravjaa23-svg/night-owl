import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The owl chosen in the approved design reference.
class NightOwlMark extends StatelessWidget {
  final double size;
  const NightOwlMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/icons/night_owl_mark.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
}

class NightOwlBrand extends StatelessWidget {
  final double size;
  final bool onDark;
  const NightOwlBrand({super.key, this.size = 28, this.onDark = false});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Night Owl',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          NightOwlMark(size: size + 2),
          const SizedBox(width: 8),
          Text('night owl',
              style: TextStyle(
                fontSize: size * .78,
                fontWeight: FontWeight.w700,
                letterSpacing: -.65,
                color:
                    onDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              )),
        ]),
      );
}
