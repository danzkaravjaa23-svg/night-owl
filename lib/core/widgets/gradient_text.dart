import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Gradient shimmer text — matches .ns-grad-text CSS class
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient gradient;

  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = AppColors.accentGradient,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: baseStyle),
    );
  }
}

/// The "Night Owl" wordmark (capital N and O); the brand name is shared across
/// locales.
class NightOwlLogoText extends StatelessWidget {
  final double fontSize;
  final bool isMn;
  final bool onDark;
  final Color? color;

  const NightOwlLogoText(
      {super.key,
      this.fontSize = 22,
      this.isMn = false,
      this.onDark = false,
      this.color});

  @override
  Widget build(BuildContext context) {
    final dark = onDark || AppColors.isDarkMode;
    final first = color ??
        (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);
    return Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Night ', style: TextStyle(color: first)),
          TextSpan(
              text: 'Owl',
              style: TextStyle(color: dark ? first : AppColors.accentStart)),
        ]),
        style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -.7));
  }
}
