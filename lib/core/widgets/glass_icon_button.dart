import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Шилэн дугуй icon товч — апп даяар НЭГ хувилбар.
/// (Өмнө нь ижил зорилготой 9 хувийн класс байсан: дүүргэлт нь bgElevated .72 /
/// bgSurface .6 / bgBase .55 / хар .45, хэмжээ 40–42, icon 17–20 гэж зөрдөг байв.)
///
/// Гаднах хүрэх талбар ХАМГИЙН БАГА 44×44 — [size] 40 байсан ч хүрэлцэхүйц.
/// Зураг/видеон дээр байрлах үед [onMedia] = true — бараан дүүргэлт, цагаан icon.
class GlassIconButton extends StatefulWidget {
  /// Товчны дотор харагдах icon.
  final IconData icon;

  /// null бол дарагдахгүй (курсор ч солигдохгүй).
  final VoidCallback? onTap;

  /// Харагдах шилэн дискний диаметр.
  final double size;

  /// Icon-ы хэмжээ.
  final double iconSize;

  /// Медиа (зураг/видео) дээр байрлаж байгаа эсэх — бараан дүүргэлт.
  final bool onMedia;

  /// Байвал Tooltip-оор ороож өгнө (монгол текст).
  final String? tooltip;

  /// Icon-ы өнгийг дарж бичих (жишээ нь идэвхтэй үеийн неон өнгө).
  final Color? iconColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.iconSize = 20,
    this.onMedia = false,
    this.tooltip,
    this.iconColor,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _down = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    // Хүрэх талбар 44-өөс багагүй — дискийг төвд нь байрлуулна.
    final hit = math.max(widget.size, 44.0);

    Widget button = SizedBox(
      width: hit,
      height: hit,
      child: Center(
        // Дарахад зөөлөн агших — апп-ын TapScale идиомтой ижил
        child: AnimatedScale(
          scale: _down ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.onMedia
                  ? Colors.black.withValues(alpha: 0.45)
                  : AppColors.dynBgElevated.withValues(alpha: 0.72),
              border: Border.all(
                color: widget.onMedia
                    ? AppColors.hairline2
                    : AppColors.dynHairline,
                width: 1,
              ),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.iconColor ??
                  (widget.onMedia ? Colors.white : AppColors.dynTextPrimary),
            ),
          ),
        ),
      ),
    );

    button = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: _enabled ? () => setState(() => _down = false) : null,
        child: button,
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
