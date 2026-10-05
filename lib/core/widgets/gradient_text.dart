import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

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

/// The approved lowercase wordmark; the brand name is shared across locales.
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
          TextSpan(text: 'night ', style: TextStyle(color: first)),
          TextSpan(
              text: 'owl',
              style: TextStyle(color: dark ? first : AppColors.accentStart)),
        ]),
        style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -.7));
  }
}
