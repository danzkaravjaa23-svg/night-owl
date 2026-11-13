/// Settings-style grouped list kit: section label, rounded card of rows,
/// inset dividers and a compact switch. Moved out of the Settings screen
/// (design plan DS-05) so privacy, account and admin screens can share one
/// look. It renders exactly like the former private Settings widgets.
///
/// Settings lays a section out like this (keep the rhythm when adopting):
///
/// ```dart
/// const SizedBox(height: 28), // between sections
/// const SettingsSectionLabel('Таны бүртгэл'),
/// const SizedBox(height: 12), // label to card
/// SettingsCard(children: [
///   SettingsRow(
///       icon: AppIcons.profile,
///       title: 'Профайл засах',
///       subtitle: 'Нэр, зураг, танилцуулга',
///       onTap: openEditProfile),
///   const SettingsDivider(),
///   SettingsRow(
///       icon: AppIcons.notifications,
///       title: 'Апп доторх мэдэгдэл',
///       onTap: () => setNotifications(!notificationsOn), // text toggles too
///       trailing: SettingsSwitch(
///           value: notificationsOn, onChanged: setNotifications)),
/// ]),
/// ```
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_text_styles.dart';

/// Narrow phone with large text: rows drop their icon tile so the copy keeps
/// its width, and [SettingsDivider] pulls its inset in to match.
bool _compactRows(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 380 &&
    MediaQuery.textScalerOf(context).scale(14) > 19;

/// Small heading above a [SettingsCard] (`labelLg` in `textSecondary`,
/// 6 px left inset).
class SettingsSectionLabel extends StatelessWidget {
  final String label;
  const SettingsSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(
          label,
          style: AppTextStyles.labelLg.copyWith(color: AppColors.textSecondary),
        ),
      );
}

/// Rounded `bgElevated` card (radius 20, 6 px padding) that stacks its
/// [children] in a column. Put a [SettingsDivider] between rows yourself.
///
/// The card is a [Material], so the ink ripple of any row inside it (a
/// [SettingsRow] or a custom `ListTile`/`InkWell` row) paints on the card
/// instead of being hidden under a coloured box.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(children: children),
        ),
      );
}

/// 1 px hairline between rows of a [SettingsCard], inset 56 px on the left
/// (12 px when rows hide their icon tile) and 12 px on the right.
class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
            left: _compactRows(context) ? 12 : 56, right: 12),
        child: Divider(height: 1, thickness: 1, color: AppColors.hairline),
      );
}

/// One settings row: violet icon tile, [title] with optional [subtitle] and
/// [value] lines, then [trailing] (or a chevron when the row is tappable).
///
/// A row with a [SettingsSwitch] passes the same toggle to [onTap], so a tap
/// on the text flips it too; screen readers get the row and its switch as one
/// node, like a `SwitchListTile`. When [enabled] is false the row is dimmed to
/// 55 %, the icon turns grey, the chevron hides and [onTap] is ignored;
/// [trailing] is left as given, so disable a switch with `onChanged: null`.
class SettingsRow extends StatelessWidget {
  /// Icon in the 36 px tile. The tile is hidden on narrow screens with large
  /// text so the copy keeps its width.
  final IconData icon;

  /// Row title (`h3`).
  final String title;

  /// Description under the title (`bodySm`, `textSecondary`).
  final String? subtitle;

  /// Value under the title in `textTertiary`, e.g. a version number.
  final String? value;

  /// Draws [value] in the mono font at 12 px instead of `bodySm`.
  final bool monospaceValue;

  /// Widget at the end of the row, e.g. a [SettingsSwitch]. Replaces the
  /// chevron.
  ///
  /// It is laid out at its natural width next to the title and never wraps,
  /// so only compact widgets (a [SettingsSwitch], an icon) belong here. Put a
  /// text button on its own line under the row instead.
  final Widget? trailing;

  /// Makes the whole row tappable (ink ripple, click cursor).
  final VoidCallback? onTap;

  /// False dims the row and ignores [onTap] (идэвхгүй мөр: сааралдуулж,
  /// дарагдахгүй).
  final bool enabled;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.monospaceValue = false,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = enabled ? AppColors.accentText : AppColors.textTertiary;
    final compact = _compactRows(context);
    final row = Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
        child: Row(
          children: [
            // At larger text sizes, give the description the icon's space.
            if (!compact) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(child: Icon(icon, size: 21, color: iconColor)),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppTextStyles.h3),
                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      subtitle!,
                      style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.textSecondary, height: 1.45),
                    ),
                  ],
                  if (value != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      value!,
                      style: monospaceValue
                          ? AppTextStyles.mono.copyWith(
                              color: AppColors.textTertiary, fontSize: 12)
                          : AppTextStyles.bodySm
                              .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null && enabled) ...[
              const SizedBox(width: 4),
              Icon(AppIcons.forward, size: 18, color: AppColors.textTertiary),
            ],
          ],
        ),
      ),
    );

    final Widget result = (onTap == null || !enabled)
        ? row
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: row,
              ),
            ),
          );
    // Like SwitchListTile: the title, the on/off state and one tap action
    // form one screen-reader node. Without this the row's tap and the
    // switch's tap conflict and the switch is announced without a name.
    return trailing is SettingsSwitch ? MergeSemantics(child: result) : result;
  }
}

/// Compact violet switch for [SettingsRow.trailing]: a 46×28 track inside a
/// 44 px tall tap target, with toggled/enabled semantics. A null [onChanged]
/// makes it inert without dimming it (a disabled [SettingsRow] dims it).
class SettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Дүрс нь 46×28 хэвээр, харин дарах талбайг 44px өндөр болгов
    return Semantics(
        toggled: value,
        enabled: onChanged != null,
        child: MouseRegion(
          cursor:
              onChanged == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(!value),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 44,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 46,
                  height: 28,
                  padding: const EdgeInsets.all(3),
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: value ? AppColors.accentStart : AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          value ? AppColors.accentStart : AppColors.hairline2,
                    ),
                  ),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value ? Colors.white : AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}
