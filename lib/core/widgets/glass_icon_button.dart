import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'sculpted_icon.dart';
import 'app_motion.dart';

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
        child: PressFeedback(
          enabled: _enabled,
          pressedScale: .94,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.onMedia
                    ? const [Color(0xD9413A55), Color(0xD9171421)]
                    : Theme.of(context).brightness == Brightness.dark
                        ? const [Color(0xFF302B46), Color(0xFF151827)]
                        : const [Color(0xFFFFFFFF), Color(0xFFE5DFF4)],
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(
                        alpha:
                            widget.onMedia || AppColors.isDarkMode ? .25 : .10),
                    offset: const Offset(0, 3),
                    blurRadius: 7),
              ],
              border: Border.all(
                // Медиа дээр горимоос үл хамааран цагаан шилэн ирмэг
                color: widget.onMedia
                    ? AppColors.hairline2Dark
                    : AppColors.isDarkMode
                        ? const Color(0xFF4B435F)
                        : const Color(0xFFD4CCE6),
                width: 1,
              ),
            ),
            child: Center(
                child: SculptedIcon(
              widget.icon,
              size: widget.iconSize,
              color: widget.iconColor ??
                  (widget.onMedia ? Colors.white : AppColors.dynTextPrimary),
              onDark: widget.onMedia,
            )),
          ),
        ),
      ),
    );

    button = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: button,
      ),
    );

    button = Semantics(
        button: true, enabled: _enabled, label: widget.tooltip, child: button);
    if (widget.tooltip != null) {
      button = Tooltip(
          message: widget.tooltip!, excludeFromSemantics: true, child: button);
    }
    return button;
  }
}
