import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import 'app_motion.dart';

/// Material's height cap for a sheet that is not scroll-controlled.
const double _kScrollControlDisabledMaxHeightRatio = 9.0 / 16.0;

/// Shows a modal bottom sheet with the Night Owl defaults (DS-02). Use it
/// instead of calling [showModalBottomSheet] directly.
///
/// Defaults that differ from [showModalBottomSheet]:
/// * `useRootNavigator: true` — the sheet is pushed on the root navigator,
///   so a sheet opened from a shell tab (feed, explore, reels, messages,
///   profile) covers and dims the dock instead of sitting above it.
/// * `isScrollControlled: true` — the sheet is as tall as its content, up to
///   the full screen. Tall content brings its own scroll view or height.
/// * `useSafeArea: true` — the sheet stays below the status bar. The content
///   still owns the bottom inset (`SafeArea(top: false, ...)`) and, when it
///   has text fields, `MediaQuery.viewInsetsOf(context).bottom`.
/// * `sheetAnimationStyle` follows [AppMotion]: 280/200 ms, and no animation
///   when the system reduces motion.
///
/// AppTheme's `bottomSheetTheme` supplies the background, the top radius and
/// the one drag handle. For a normal sheet do not pass `backgroundColor`,
/// `shape` or `showDragHandle`, and never draw a handle inside the content.
/// Start a sheet that has a title with [AppSheetHeader].
///
/// **Close the sheet with the SHEET's own BuildContext** — the context the
/// [builder] receives, or any context inside the sheet:
/// `Navigator.of(sheetContext).pop(result)`. With `useRootNavigator` the
/// sheet is not on the page's navigator, so `Navigator.of(pageContext).pop()`
/// (or `Navigator.pop(pageContext)`) pops the PAGE underneath and leaves the
/// sheet open. go_router's `context.pop()` is not safe either: go_router 13
/// pops the deepest nested navigator that can pop, which can be the page
/// under the sheet. Once the sheet has closed, keep using the page's context
/// for navigation and snack bars.
///
/// Other effects of the root navigator:
/// * A SnackBar shown while the sheet stays open is painted under the sheet.
///   Show the error inside the sheet, or close the sheet first.
/// * Lookups from inside the sheet no longer see widgets between the page
///   and the root navigator, such as the shell's Scaffold ([Scaffold.of]
///   throws there). Riverpod providers, [ScaffoldMessenger], GoRouter and
///   MediaQuery still resolve.
/// * Android back closes the topmost route on the root navigator (this
///   sheet, or a dialog opened from it) even when a nested navigator
///   underneath has its own back stack.
///
/// [dark] is for sheets opened from always-dark screens (reels, story viewer
/// and editor, live). The whole sheet (background, drag handle and the
/// Material defaults of its content) uses [AppTheme.dark], in the Day theme
/// too. The adaptive [AppColors] getters (`textPrimary`, `bgSurface`, …) and
/// [AppTextStyles] follow the APP mode, not this theme, so the content of a
/// dark sheet takes its colours from `Theme.of(context)`, the `*Dark`
/// constants or `.onDark`.
///
/// The remaining parameters match [showModalBottomSheet].
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dark = false,
  bool useRootNavigator = true,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  Color? backgroundColor,
  Color? barrierColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  double scrollControlDisabledMaxHeightRatio =
      _kScrollControlDisabledMaxHeightRatio,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  assert(debugCheckHasMediaQuery(context));
  assert(debugCheckHasMaterialLocalizations(context));
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  final ThemeData? sheetTheme = dark ? AppTheme.dark : null;
  final bottomSheetTheme = (sheetTheme ?? Theme.of(context)).bottomSheetTheme;
  return navigator.push(_AppSheetRoute<T>(
    sheetTheme: sheetTheme,
    builder: sheetTheme == null ? builder : _themed(sheetTheme, builder),
    capturedThemes:
        InheritedTheme.capture(from: context, to: navigator.context),
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    barrierLabel: barrierLabel ?? localizations.scrimLabel,
    barrierOnTapHint:
        localizations.scrimOnTapHint(localizations.bottomSheetLabel),
    // A dark sheet names its background so a light Theme captured from the
    // caller cannot override it.
    backgroundColor: backgroundColor ??
        (sheetTheme == null
            ? null
            : bottomSheetTheme.modalBackgroundColor ??
                bottomSheetTheme.backgroundColor),
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    isDismissible: isDismissible,
    modalBarrierColor: barrierColor ?? bottomSheetTheme.modalBarrierColor,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    settings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    useSafeArea: useSafeArea,
    sheetAnimationStyle: sheetAnimationStyle ?? _sheetMotion(context),
    requestFocus: requestFocus,
  ));
}

AnimationStyle _sheetMotion(BuildContext context) => AppMotion.reduced(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.enter, reverseDuration: AppMotion.exit);

/// Builds the content below [theme], so even a Theme captured from the
/// caller cannot turn a dark sheet's content light.
WidgetBuilder _themed(ThemeData theme, WidgetBuilder builder) =>
    (context) => Theme(data: theme, child: Builder(builder: builder));

class _AppSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AppSheetRoute({
    required this.sheetTheme,
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.scrollControlDisabledMaxHeightRatio,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.isDismissible,
    super.modalBarrierColor,
    super.enableDrag,
    super.showDragHandle,
    super.settings,
    super.transitionAnimationController,
    super.anchorPoint,
    super.useSafeArea,
    super.sheetAnimationStyle,
    super.requestFocus,
  });

  /// Theme of the whole sheet (its background, drag handle and content), or
  /// null to follow the app theme.
  final ThemeData? sheetTheme;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    var page = super.buildPage(context, animation, secondaryAnimation);
    final theme = sheetTheme;
    // ModalBottomSheetRoute reads the background, shape and drag handle
    // colour from the Theme around the route, so a dark sheet wraps all of
    // it, not only the builder's content.
    if (theme != null) page = Theme(data: theme, child: page);
    // go_router 13 sends Android back to the deepest nested navigator that
    // can pop, which is the page UNDER a sheet on the root navigator. A root
    // sheet answers back first and pops the root navigator's top route.
    final dispatcher = Router.maybeOf(context)?.backButtonDispatcher;
    final root = Navigator.maybeOf(context, rootNavigator: true);
    if (dispatcher != null && identical(navigator, root)) {
      page = BackButtonListener(onBackButtonPressed: _onBack, child: page);
    }
    return page;
  }

  Future<bool> _onBack() async {
    final navigator = this.navigator;
    if (navigator == null || !isActive) return false;
    return navigator.maybePop();
  }
}

/// Title row of a sheet (DS-02): [title] in `AppTextStyles.title`, an
/// optional [subtitle], [trailing] actions and a close button.
///
/// It sits right under the theme's drag handle, so it adds no top padding
/// (give it one through [padding] in a sheet without a handle, e.g.
/// `enableDrag: false`). Colours come from the sheet's Theme, so it also
/// reads correctly inside `showAppSheet(dark: true)`. The close button pops
/// with the header's own (sheet) context unless [onClose] is given.
class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showClose = false,
    this.onClose,
    this.padding = const EdgeInsets.fromLTRB(
        AppSpacing.page, 0, AppSpacing.x2, AppSpacing.x2),
  });

  final String title;
  final String? subtitle;

  /// Actions before the close button, e.g. a TextButton "Хасах".
  final Widget? trailing;

  /// Shows an "Хаах" button. Implied when [onClose] is set.
  final bool showClose;

  /// Replaces the default close action (popping the sheet).
  final VoidCallback? onClose;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondary =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final subtitle = this.subtitle;
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // No line cap: titles can be user content (a venue name, a
              // report question) and must stay whole at large text sizes.
              Semantics(
                header: true,
                child: Text(title,
                    style: AppTextStyles.title.copyWith(color: primary)),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(color: secondary)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (showClose || onClose != null)
          IconButton(
            tooltip: 'Хаах',
            onPressed: onClose ?? () => Navigator.of(context).maybePop(),
            icon: Icon(AppIcons.close, color: secondary),
          ),
      ]),
    );
  }
}
