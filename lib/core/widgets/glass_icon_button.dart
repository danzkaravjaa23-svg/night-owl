import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_text_styles.dart';
import 'sculpted_icon.dart';
import 'app_motion.dart';

/// Шилэн дугуй icon товч — апп даяар НЭГ хувилбар.
/// (Өмнө нь ижил зорилготой 9 хувийн класс байсан: дүүргэлт нь bgElevated .72 /
/// bgSurface .6 / bgBase .55 / хар .45, хэмжээ 40–42, icon 17–20 гэж зөрдөг байв.)
///
/// Гаднах хүрэх талбар ХАМГИЙН БАГА 44×44 — [size] 40 байсан ч хүрэлцэхүйц.
/// Зураг/видеон дээр байрлах үед [onMedia] = true — бараан дүүргэлт, цагаан icon.
///
/// Badge (feed-ийн хуучин `_TopIconBtn`-ийг орлоно, DS-06): [badgeCount] > 0 бол
/// дискийн баруун дээд буланд тоо ("99+" хүртэл), [showBadgeDot] бол тоогүй цэг.
/// [AppColors.dangerFill] дээр цагаан 10px текст (≈5:1 контраст, хуучин
/// #FF4566 дээрх 9px нь 3.3:1 байсан — DS-01), эргэн тойронд нь ард байгаа
/// гадаргуугийн өнгөтэй 1.5px цагираг. Дэлгэц уншигч тоог товчны шошгоор
/// сонсоно: "Мэдэгдэл, 3 шинэ". Tooltip нь тоогүй хэвээр ("Мэдэгдэл").
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

  /// Шинэ зүйлсийн тоо. 0 (эсвэл сөрөг) бол тоон badge харагдахгүй.
  /// 99-өөс их бол "99+" гэж харуулна; дэлгэц уншигч бодит тоог сонсоно.
  final int badgeCount;

  /// Тоогүй "шинэ зүйл байна" цэг (8px). [badgeCount] > 0 үед тоо давамгайлна.
  final bool showBadgeDot;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.iconSize = 20,
    this.onMedia = false,
    this.tooltip,
    this.iconColor,
    this.badgeCount = 0,
    this.showBadgeDot = false,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  // Badge-ийн хэмжээс: улаан pill хамгийн багадаа 16×16, цэг 8×8; гадна нь
  // 1.5px цагираг (нийт 19 / 11). Текст 1.3×-ээс илүү томрохгүй — том текстийн
  // горимд ч 40px дискийг бүрхэхгүй (тоо нь шошгоор бүрэн сонсогдоно).
  static const double _ringWidth = 1.5;
  static const double _pillMin = 16;
  static const double _dotSize = 8;
  static const double _maxBadgeTextScale = 1.3;

  bool get _enabled => widget.onTap != null;
  bool _focused = false;

  bool get _hasCount => widget.badgeCount > 0;
  bool get _hasDot => !_hasCount && widget.showBadgeDot;

  /// Дэлгэц уншигчийн шошго: tooltip + шинэ зүйлс ("Мэдэгдэл, 3 шинэ").
  String? get _semanticLabel {
    final tooltip = widget.tooltip;
    final status = _hasCount
        ? '${widget.badgeCount} шинэ'
        : _hasDot
            ? 'шинэ'
            : null;
    final parts = [
      if (tooltip != null && tooltip.isNotEmpty) tooltip,
      if (status != null) status,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

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
          // Badge нь дисктэй хамт агшина. Stack үргэлж байх тул badge гарч
          // ирэх/алга болоход дискний төлөв (focus хүрээ) дахин үүсэхгүй.
          child: Stack(clipBehavior: Clip.none, children: [
            AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.exit),
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
                          alpha: widget.onMedia || AppColors.isDarkMode
                              ? .25
                              : .10),
                      offset: const Offset(0, 3),
                      blurRadius: 7),
                ],
                border: Border.all(
                  // Медиа дээр горимоос үл хамааран цагаан шилэн ирмэг
                  color: _focused && _enabled
                      ? (widget.onMedia ? Colors.white : AppColors.neonCyan)
                      : widget.onMedia
                          ? AppColors.hairline2Dark
                          : AppColors.isDarkMode
                              ? const Color(0xFF4B435F)
                              : const Color(0xFFD4CCE6),
                  width: _focused && _enabled ? 2 : 1,
                ),
              ),
              child: Center(
                  child: SculptedIcon(
                widget.icon,
                size: widget.iconSize,
                color: !_enabled
                    ? (widget.onMedia
                        ? Colors.white54
                        : AppColors.dynTextTertiary)
                    : widget.iconColor ??
                        (widget.onMedia
                            ? Colors.white
                            : AppColors.dynTextPrimary),
                onDark: widget.onMedia,
              )),
            ),
            if (_hasCount || _hasDot) _badge(context),
          ]),
        ),
      ),
    );

    button = IconButton(
      onPressed: widget.onTap,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: hit, height: hit),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
        foregroundColor: widget.onMedia ? Colors.white : AppColors.neonCyan,
      ),
      icon: button,
    );
    button = Focus(
      canRequestFocus: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: button,
    );

    // Нэг semantics node: шошго (tooltip + шинэ зүйлсийн тоо), button төлөв,
    // дарах үйлдэл бүгд нэг дор — дэлгэц уншигч товчийг нэг л удаа уншина.
    button = MergeSemantics(
      child: Semantics(
          button: true,
          enabled: _enabled,
          label: _semanticLabel,
          child: button),
    );
    if (widget.tooltip != null) {
      button = Tooltip(
          message: widget.tooltip!, excludeFromSemantics: true, child: button);
    }
    return button;
  }

  /// Дискийн баруун дээд буланд (дугуйн 45°-ийн цэг дээр төвтэй) badge.
  /// Хуучин feed badge-тай ижил байрлал бөгөөд ямар ч [GlassIconButton.size]-д
  /// ажиллана; өргөн "99+" зүүн тийш (icon руу) тэлнэ.
  Widget _badge(BuildContext context) {
    final corner = widget.size / 2 * (1 - math.sqrt1_2);
    // Цагираг нь ард байгаа гадаргуугийн өнгөтэй байж badge-ийг дискээс салгана.
    final ring = widget.onMedia ? AppColors.bgBaseDark : AppColors.bgBase;
    final extent = (_hasCount ? _pillMin : _dotSize) + _ringWidth * 2;

    final Widget badge = _hasCount
        ? Container(
            constraints: BoxConstraints(minWidth: extent, minHeight: extent),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.dangerFill,
              borderRadius: AppRadii.pillR,
              border: Border.all(color: ring, width: _ringWidth),
              boxShadow: [
                BoxShadow(
                    color: AppColors.dangerFill.withValues(alpha: .45),
                    blurRadius: 6),
              ],
            ),
            child: Text(
              widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
              maxLines: 1,
              softWrap: false,
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: _maxBadgeTextScale),
              // Тоо солигдоход өргөн нь үсрэхгүй — tabular цифр.
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          )
        : Container(
            width: extent,
            height: extent,
            decoration: BoxDecoration(
              color: AppColors.dangerFill,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: _ringWidth),
            ),
          );

    return PositionedDirectional(
      top: corner - extent / 2,
      end: corner - extent / 2,
      // Чимэглэл: дарах үйлдэл ба шошгыг товч өөрөө эзэмшинэ.
      child: IgnorePointer(child: ExcludeSemantics(child: badge)),
    );
  }
}
