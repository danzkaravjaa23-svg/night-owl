import 'package:flutter/material.dart';
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

/// Night Owl logo text widget
class NightOwlLogoText extends StatelessWidget {
  final double fontSize;
  final bool isMn;

  const NightOwlLogoText({
    super.key,
    this.fontSize = 22,
    this.isMn = false,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        children: [
          TextSpan(text: isMn ? 'Шөнийн ' : 'Night'),
          WidgetSpan(
            child: GradientText(
              isMn ? 'шувуухай' : ' Owl',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
