import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text_styles.dart';

/// Шилэн pill хайлтын талбар — апп даяар НЭГ хувилбар.
/// (Өмнө нь ижил "хэрэглэгч хайх" талбар гурван өөр хэлбэртэй байв: pill,
/// сэдвийн бүдүүн хайрцаг, 52 өндөртэй glow-той pill.)
///
/// Хэмжээ: өндөр 48 · pill радиус · bgSurface 0.7 дүүргэлт · hairline хүрээ ·
/// зүүн icon 19, дараа нь 10px зай. Focus үед неон cyan ирмэг + зөөлөн glow.
/// Энгийн pill input (жишээ нь группийн нэр) болгон ч ашиглаж болно.
class SearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hint;

  /// Зүүн талын icon (хайлтад Icons.search).
  final IconData icon;
  final bool autofocus;

  /// Текст байх үед баруун талд цэвэрлэх ✕ товч харуулах эсэх.
  final bool showClear;

  /// ✕ дарсны дараа эцэг дэлгэц нэмэлт үйлдэл хийх бол (жишээ нь хайлт цэвэрлэх).
  /// Байхгүй бол зөвхөн controller цэвэрлэгдэж [onChanged]('') дуудагдана.
  final VoidCallback? onClear;

  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon = Icons.search,
    this.onChanged,
    this.autofocus = false,
    this.showClear = true,
    this.onClear,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  bool _focus = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onCtrl);
  }

  // Зөвхөн "хоосон ↔ хоосон биш" солигдоход л дахин зурна
  void _onCtrl() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    super.dispose();
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    height: 48,
    decoration: BoxDecoration(
      color: AppColors.bgSurface.withValues(alpha: 0.7),
      borderRadius: AppRadii.pillR,
      border: Border.all(color: _focus
          ? AppColors.neonCyan.withValues(alpha: 0.6)
          : AppColors.hairline),
      boxShadow: _focus
          ? [
              BoxShadow(
                color: AppColors.neonCyan.withValues(alpha: 0.18),
                blurRadius: 16, spreadRadius: -2),
            ]
          : null),
    child: Row(children: [
      const SizedBox(width: 16),
      Icon(widget.icon, size: 19,
        color: _focus ? AppColors.neonCyan : AppColors.textTertiary),
      const SizedBox(width: 10),
      Expanded(child: Focus(
        onFocusChange: (f) => setState(() => _focus = f),
        child: TextField(
          controller: widget.controller,
          onChanged: widget.onChanged,
          autofocus: widget.autofocus,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
          cursorColor: AppColors.neonCyan,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textTertiary),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true, contentPadding: EdgeInsets.zero)))),
      // Цэвэрлэх — хүрэх талбар 44×44, глиф 16 хэвээр
      if (widget.showClear && _hasText)
        _ClearBtn(onTap: _clear)
      else
        const SizedBox(width: 16),
    ]));
}

/// ✕ цэвэрлэх товч — 44×44 хүрэх талбар, ripple-гүй агших press идиом
class _ClearBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _ClearBtn({required this.onTap});
  @override
  State<_ClearBtn> createState() => _ClearBtnState();
}

class _ClearBtnState extends State<_ClearBtn> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: const SizedBox(width: 44, height: 44,
          child: Center(child: Icon(Icons.close,
            size: 16, color: AppColors.textTertiary))),
      ),
    ),
  );
}
