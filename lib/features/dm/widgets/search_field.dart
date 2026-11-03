import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Shared search input with a visible focus ring and an accessible clear action.
class SearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hint;
  final IconData icon;
  final bool autofocus;
  final bool showClear;
  final VoidCallback? onClear;

  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon = Icons.search_rounded,
    this.onChanged,
    this.autofocus = false,
    this.showClear = true,
    this.onClear,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _focusNode.addListener(_refresh);
  }

  @override
  void didUpdateWidget(SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 54),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _focusNode.hasFocus
                ? AppColors.neonCyan.withValues(alpha: .65)
                : AppColors.hairline2,
            width: _focusNode.hasFocus ? 1.5 : 1,
          ),
          boxShadow: _focusNode.hasFocus
              ? [
                  BoxShadow(
                      color: AppColors.accentStart.withValues(alpha: .08),
                      blurRadius: 14)
                ]
              : null,
        ),
        child: Row(children: [
          const SizedBox(width: 16),
          Icon(widget.icon,
              size: 21,
              color: _focusNode.hasFocus
                  ? AppColors.neonCyan
                  : AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.bodyMd.copyWith(fontSize: 15),
              cursorColor: AppColors.neonCyan,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textTertiary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (widget.showClear && widget.controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Цэвэрлэх',
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                fixedSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
              ),
              onPressed: _clear,
              icon: Icon(Icons.cancel_rounded,
                  size: 20, color: AppColors.textSecondary),
            )
          else
            const SizedBox(width: 16),
        ]),
      );
}
