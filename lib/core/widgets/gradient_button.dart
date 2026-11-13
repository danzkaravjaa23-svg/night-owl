/// Night Owl button system (DS-03). Every button is a pill.
///
/// * [GradientButton] is the PRIMARY action: the one main action of a region
///   (a page footer, a sheet, an empty state, a list row). Violet
///   `AppGradients.primary` fill, white label, the owl while busy. Use one
///   per region; any other action next to it is secondary or tertiary.
///   Sizes: [GradientButtonSize.lg] 52 px (default: page and sheet CTAs),
///   [GradientButtonSize.md] 44 px (empty states, inline actions),
///   [GradientButtonSize.sm] 36 px pill with a 44 px tap target (row actions
///   such as "Дагах" in lists and on reels).
/// * [OutlineButton] is the SECONDARY action ("Болих" next to "Хадгалах").
/// * The themed [TextButton] is the TERTIARY action: low-emphasis text such
///   as "Бүгдийг харах" or "Дахин оролдох" inside a row.
/// * Material [FilledButton], [ElevatedButton] and [OutlinedButton] are
///   themed as pills by AppTheme for plain cases (dialogs, settings, admin
///   tools). A destructive confirmation is a [FilledButton] on
///   `AppColors.dangerFill` with a white label.
///
/// Do not hand-build a primary button from a gradient Container inside a
/// GestureDetector or InkWell: it loses the busy and disabled states,
/// keyboard focus, semantics and the 44 px tap target.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_text_styles.dart';
import 'app_motion.dart';
import 'owl_loading.dart';
import 'premium_surface.dart';
import 'sculpted_icon.dart';

/// Pill outline shared by the primary and secondary buttons.
const BorderRadius _pillRadius =
    BorderRadius.all(Radius.circular(AppRadii.pill));

/// Smallest tap target any button keeps (WCAG 2.5.8 / iOS HIG 44 pt).
const double _kMinTapTarget = 44;

/// Visual height of a [GradientButtonSize.sm] pill.
const double _kCompactHeight = 36;

/// Draws an [Icon] child as a [SculptedIcon]: white on the primary gradient,
/// otherwise the icon's own colour. [color] overrides both, e.g. the
/// tertiary grey of a disabled button. Other widgets pass through unchanged.
Widget _dimensionalButtonIcon(Widget child,
    {bool primary = false, Color? color}) {
  if (child is Icon && child.icon != null) {
    return SculptedIcon(child.icon!,
        size: child.size ?? 20,
        color: color ?? (primary ? Colors.white : child.color),
        onDark: primary);
  }
  return child;
}

/// Primary товчны хэмжээ (бүгд pill хэлбэртэй):
/// * [lg] — 52 px, дэлгэц ба sheet-ийн үндсэн CTA (анхдагч).
/// * [md] — 44 px, хоосон төлөв, мөр доторх товч.
/// * [sm] — 36 px pill, хүрэх талбар нь 44 px хэвээр: жагсаалтын мөр,
///   reels дээрх "Дагах" зэрэг нягт үйлдэл.
enum GradientButtonSize { lg, md, sm }

/// Primary gradient button — CSS .ns-btn-primary. Always pill-shaped.
/// Дарахад зөөлөн агшиж (spring press) премиум мэдрэмж өгнө.
/// busy=true үед үйлдлийн нэрийг хадгалж, owl төлөвийг хамт харуулна.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Widget? trailing;

  /// Хамгийн бага өндөр. Том бичвэртэй үед агуулгадаа тохирч өснө.
  /// lg/md: at least 44. sm: height of the visible pill (at least 32); its
  /// tap target stays 44.
  final double? height;
  final bool busy;
  final GradientButtonSize size;

  /// false бол агуулгынхаа өргөнөөр (мөрөнд зэрэгцүүлэхэд).
  final bool fullWidth;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailing,
    this.height,
    this.busy = false,
    this.size = GradientButtonSize.lg,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final compact = size == GradientButtonSize.sm;
    final double h = switch (size) {
      GradientButtonSize.lg => math.max(height ?? 52.0, 44.0),
      GradientButtonSize.md => math.max(height ?? 44.0, 44.0),
      GradientButtonSize.sm => math.max(height ?? _kCompactHeight, 32.0),
    };
    final TextStyle baseLabel = switch (size) {
      GradientButtonSize.lg => AppTextStyles.btn,
      GradientButtonSize.md => AppTextStyles.btnSm,
      GradientButtonSize.sm =>
        AppTextStyles.btnSm.copyWith(fontWeight: FontWeight.w700),
    };
    // Gradient дээрх label — горимоос үл хамааран цэвэр цагаан (#FFFFFF):
    // AppGradients.primary-ийн цайвар зүүн дээд хэсэгт буух эхний үсэг ч
    // 4.5:1 хүрнэ (#F5F5FC агуулгын өргөнтэй товчинд 4.2–4.4:1 байв).
    final labelStyle = baseLabel.copyWith(color: Colors.white);
    final double paddingX = switch (size) {
      GradientButtonSize.lg => 20.0,
      GradientButtonSize.md => 16.0,
      GradientButtonSize.sm => 14.0,
    };
    final double owlSize = switch (size) {
      GradientButtonSize.lg => 24.0,
      GradientButtonSize.md => 18.0,
      GradientButtonSize.sm => 16.0,
    };
    // busy үед gradient хэвээр (ажиллаж буй мэдрэмж), зөвхөн disabled үед бүдгэрнэ
    final disabled = onPressed == null && !busy;
    final effective = (busy || disabled) ? null : onPressed;
    final Widget button = PressFeedback(
      enabled: effective != null,
      child: ActionSheen(
          radius: AppRadii.pill,
          enabled: effective != null,
          child: SizedBox(
            width: fullWidth ? double.infinity : null,
            child: AnimatedContainer(
              constraints: BoxConstraints(minHeight: h),
              duration: AppMotion.duration(context, AppMotion.exit),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: !disabled
                    ? AppGradients.primary
                    : LinearGradient(colors: [
                        AppColors.dynBgSurface,
                        AppColors.dynBgSurface
                      ]),
                borderRadius: _pillRadius,
                // Шилэн ирмэг — дээд гэрлийн нарийн hairline
                border: Border.all(
                    color: !disabled
                        ? Colors.white.withValues(alpha: 0.14)
                        : AppColors.dynHairline),
                // Неон glow — magenta ойрын + pink холын давхар сүүдэр
                boxShadow: !disabled
                    ? [
                        const BoxShadow(
                            color: Color(0xFF49307B),
                            offset: Offset(0, 3),
                            blurRadius: 0),
                        BoxShadow(
                          color: AppColors.accentStart
                              .withValues(alpha: busy ? 0.10 : 0.16),
                          blurRadius: 22,
                          spreadRadius: -2,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: AppColors.accentEnd
                              .withValues(alpha: busy ? 0.06 : 0.08),
                          blurRadius: 32,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: ElevatedButton(
                onPressed: effective,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  // busy үед onPressed=null дамждаг тул M3-ийн disabled саарал
                  // gradient-ийг дардаг байв — үндсэн CTA хүлээж байхдаа
                  // идэвхгүй мэт харагдана. Тунгалаг болгож gradient-ийг хэвээр үлдээв.
                  disabledBackgroundColor: Colors.transparent,
                  disabledForegroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  minimumSize: Size(fullWidth ? double.infinity : 0, h),
                  padding: EdgeInsets.symmetric(
                      horizontal: paddingX, vertical: compact ? 6 : 8),
                  // Desktop (and desktop web) default to compact density,
                  // which takes 8 px off the padding; keep one size everywhere.
                  visualDensity: VisualDensity.standard,
                  // sm keeps its 36 px look; _MinTapTarget below supplies the
                  // 44 px target instead of Material's padding (which would
                  // grow the gradient to 48 px).
                  tapTargetSize:
                      compact ? MaterialTapTargetSize.shrinkWrap : null,
                  shape: const StadiumBorder(),
                ),
                // Спиннер ↔ label солигдоход зөөлөн fade + scale шилжилт
                child: AnimatedSwitcher(
                  duration: AppMotion.duration(context, AppMotion.exit),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                        scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                        child: child),
                  ),
                  child: busy
                      ? Semantics(
                          key: const ValueKey('busy'),
                          liveRegion: true,
                          label: '$label: түр хүлээнэ үү',
                          child: ExcludeSemantics(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OwlLoading(
                                    size: owlSize, compact: true, onDark: true),
                                SizedBox(width: compact ? 8 : 10),
                                Flexible(
                                    child: Text(label,
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: labelStyle)),
                              ],
                            ),
                          ))
                      : Row(
                          key: const ValueKey('label'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              // A white icon would vanish on the Day disabled
                              // surface, so it dims with the label.
                              _dimensionalButtonIcon(icon!,
                                  primary: !disabled,
                                  color: disabled
                                      ? AppColors.dynTextTertiary
                                      : null),
                              SizedBox(width: compact ? 6 : 8)
                            ],
                            Flexible(
                                child: Text(label,
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: !disabled
                                        ? labelStyle
                                        // Идэвхгүй товч бүдэг label-тай — disabled гэдэг нь илт
                                        : labelStyle.copyWith(
                                            color: AppColors.dynTextTertiary))),
                            if (trailing != null) ...[
                              SizedBox(width: compact ? 6 : 8),
                              trailing!
                            ],
                          ],
                        ),
                ),
              ),
            ),
          )),
    );
    if (!compact) return button;
    // One semantics node over the whole 44 px target, so the reported
    // tap area matches the real one.
    return MergeSemantics(
      child: _MinTapTarget(
        minSize: const Size.square(_kMinTapTarget),
        child: button,
      ),
    );
  }
}

/// Secondary outline button — CSS .ns-btn-secondary. Pill, like every
/// button in the system.
class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Height of the [GradientButtonSize.lg] button (default 52). md is 44
  /// and sm is a 36 px pill, exactly like [GradientButton].
  final double height;

  /// lg (default) — full-size secondary action; md — compact; sm — 36 px
  /// pill with a 44 px tap target for row actions such as "Дагасан".
  final GradientButtonSize size;

  /// false бол агуулгынхаа өргөнөөр (мөрөнд [GradientButton]-той зэрэгцүүлэхэд).
  final bool fullWidth;

  const OutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 52,
    this.size = GradientButtonSize.lg,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final compact = size == GradientButtonSize.sm;
    final double h = switch (size) {
      GradientButtonSize.lg => height,
      GradientButtonSize.md => 44.0,
      GradientButtonSize.sm => _kCompactHeight,
    };
    final double paddingX = switch (size) {
      GradientButtonSize.lg => 20.0,
      GradientButtonSize.md => 16.0,
      GradientButtonSize.sm => 14.0,
    };
    final TextStyle labelStyle = (size == GradientButtonSize.lg
            ? AppTextStyles.btn
            : AppTextStyles.btnSm)
        .copyWith(fontWeight: FontWeight.w600);
    // Disabled: tertiary label and icon on a fainter border, like the
    // disabled GradientButton (the label style's colour would otherwise win
    // over TextButton's disabled foreground).
    final disabled = onPressed == null;
    final Widget button = PressFeedback(
      enabled: onPressed != null,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.bgElevated, AppColors.bgSurface]),
            borderRadius: _pillRadius,
            border: Border.all(
                color: disabled
                    ? AppColors.dynHairline
                    : AppColors.dynHairline2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black
                      .withValues(alpha: AppColors.isDarkMode ? .16 : .06),
                  offset: const Offset(0, 3),
                  blurRadius: 6)
            ],
          ),
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              minimumSize: Size(fullWidth ? double.infinity : 0, h),
              padding: EdgeInsets.symmetric(
                  horizontal: paddingX, vertical: compact ? 6 : 12),
              // sm keeps its 36 px look; _MinTapTarget below supplies the
              // 44 px target (same as GradientButton.sm).
              tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
              // Same height as GradientButton on desktop too, where the
              // default compact density would take 8 px off.
              visualDensity: VisualDensity.standard,
              foregroundColor: AppColors.dynTextPrimary,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  _dimensionalButtonIcon(icon!,
                      color: disabled ? AppColors.dynTextTertiary : null),
                  SizedBox(width: compact ? 6 : 8)
                ],
                Flexible(
                    child: Text(label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: disabled
                            ? labelStyle.copyWith(
                                color: AppColors.dynTextTertiary)
                            : labelStyle)),
              ],
            ),
          ),
        ),
      ),
    );
    if (!compact) return button;
    return MergeSemantics(
      child: _MinTapTarget(
        minSize: const Size.square(_kMinTapTarget),
        child: button,
      ),
    );
  }
}

/// Gives a compact control a tap target of at least [minSize] without
/// growing what is painted: the child is centred, and a tap on the
/// transparent margin is delivered to the child's centre, the same way
/// Material pads its own buttons.
class _MinTapTarget extends SingleChildRenderObjectWidget {
  const _MinTapTarget({required this.minSize, required Widget super.child});

  final Size minSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinTapTarget(minSize);

  @override
  void updateRenderObject(
      BuildContext context, _RenderMinTapTarget renderObject) {
    renderObject.minSize = minSize;
  }
}

class _RenderMinTapTarget extends RenderShiftedBox {
  _RenderMinTapTarget(this._minSize) : super(null);

  Size get minSize => _minSize;
  Size _minSize;
  set minSize(Size value) {
    if (_minSize == value) return;
    _minSize = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(super.computeMinIntrinsicWidth(height), minSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(super.computeMaxIntrinsicWidth(height), minSize.width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width), minSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width), minSize.height);

  Size _computeSize(BoxConstraints constraints, ChildLayouter layoutChild) {
    final child = this.child;
    if (child == null) return constraints.constrain(minSize);
    final childSize = layoutChild(child, constraints);
    return constraints.constrain(Size(
        math.max(childSize.width, minSize.width),
        math.max(childSize.height, minSize.height)));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _computeSize(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  double? computeDryBaseline(
      covariant BoxConstraints constraints, TextBaseline baseline) {
    final child = this.child;
    if (child == null) return null;
    final result = child.getDryBaseline(constraints, baseline);
    if (result == null) return null;
    final childSize = child.getDryLayout(constraints);
    return result +
        Alignment.center
            .alongOffset(getDryLayout(constraints) - childSize as Offset)
            .dy;
  }

  @override
  void performLayout() {
    size = _computeSize(constraints, ChildLayoutHelper.layoutChild);
    final child = this.child;
    if (child != null) {
      (child.parentData! as BoxParentData).offset =
          Alignment.center.alongOffset(size - child.size as Offset);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null || !size.contains(position)) return false;
    // A tap on the margin counts as a tap on the control's centre.
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (BoxHitTestResult result, Offset position) {
        assert(position == center);
        return child.hitTest(result, position: center);
      },
    );
  }
}
