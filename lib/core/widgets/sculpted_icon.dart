import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A small dimensional glyph. The owning button supplies its accessible label.
/// Keeping the original IconData preserves familiar actions and tap targets.
class SculptedIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final bool active;
  final bool onDark;

  const SculptedIcon(this.icon,
      {super.key,
      this.size = 24,
      this.color,
      this.active = false,
      this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    final face = color ??
        (active
            ? (dark ? AppColors.silverNeon : AppColors.accentStart)
            : (dark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight));
    final edge = Color.lerp(face, const Color(0xFF241442), dark ? .54 : .38)!;
    final highlight = Color.lerp(face, Colors.white, dark ? .38 : .18)!;
    final depth = size * .065;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: Offset(depth, depth * 1.35),
                child: Icon(icon, size: size, color: edge, shadows: [
                  Shadow(
                      color: Colors.black.withValues(alpha: dark ? .45 : .16),
                      offset: Offset(0, depth),
                      blurRadius: size * .16),
                ]),
              ),
              Transform.translate(
                offset: Offset(depth * .45, depth * .55),
                child: Icon(icon, size: size, color: edge),
              ),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [highlight, face, Color.lerp(face, edge, .18)!],
                  stops: const [0, .48, 1],
                ).createShader(bounds),
                child: Icon(icon, size: size, color: Colors.white),
              ),
            ]),
      ),
    );
  }
}
