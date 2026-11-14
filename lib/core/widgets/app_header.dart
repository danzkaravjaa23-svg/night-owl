import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart' show AppRoutes;
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'glass_icon_button.dart';
import 'night_owl_brand.dart';
import 'premium_surface.dart' show NightOwlAtmosphere;

enum _AppHeaderVariant { brand, title, media }

/// Апп даяарх НЭГ дээд толгой (DS-06). Өмнө нь 8 өөр толгой, ~10 дугуй
/// товчны хуулбар, 5 өөр буцах glyph, 14–28px гарчиг байсныг нэгтгэнэ.
///
/// Гурван хувилбар:
/// * [AppHeader.brand] — tab-ын нүүр (Feed, Explore): зүүнд NightOwlBrand,
///   баруунд үйлдлүүд.
/// * [AppHeader.title] — дэд хуудас: буцах товч + [AppTextStyles.pageTitle]
///   гарчиг (+ [AppTextStyles.caption] дэд мөр) + үйлдлүүд.
/// * [AppHeader.media] — зураг/видео дээр: тунгалаг, `onMedia` шилэн товч,
///   цагаан гарчиг.
///
/// Хэмжээс:
/// * Контентын өндөр [height] = 64.
/// * Хэвтээ gutter = [AppSpacing.page] (20). [GlassIconButton]-ийн 44px хүрэх
///   талбар 40px дискийг тал бүрт 2px-ээр тойрдог тул хүрэх талбарыг 18px-ээс
///   эхлүүлж, ДИСКИЙН ирмэгийг яг gutter дээр буулгана. Гарчиг ба брэндийн
///   үзэгдэх ирмэг ч gutter дээр эхэлнэ.
/// * Буцах дискээс гарчиг хүртэл 12px; [actions]-ийн дискүүд хооронд 8px.
///   [actions] нь [GlassIconButton] (эсвэл ThemeToggleButton) гэж тооцсон —
///   өөрөө зай нэмэх шаардлагагүй.
///
/// Дээд safe area (status bar): [primary] = true (анхдагч) үед толгой status
/// bar-ын зайг ӨӨРӨӨ авна (`AppBar.primary`-тай ижил), дэвсгэр/гэрэл нь status
/// bar-ын доогуур тасралтгүй үргэлжилнэ. Иймээс:
/// * `Scaffold(appBar: AppHeader.title(...))` — шууд ажиллана. [preferredSize]
///   нь 64 (+ [AppHeader.title]-ийн `bottom`); Scaffold status bar-ын өндрийг
///   өөрөө нэмж зай гаргадаг.
/// * Inline (Column/Stack-ийн оройд): SafeArea-ийн ГАДНА тавибал status bar-ыг
///   өөрөө тооцож, гэрэл нь status bar-ын доор зурвасгүй үргэлжилнэ (зөвлөмж).
///   SafeArea-ийн ДОТОР тавьсан ч зөв — padding аль хэдийн 0 тул давхардахгүй.
/// * Status bar-тай зэргэлдээгүй газар (sheet, карт дотор) — `primary: false`.
///
/// Том текст: гарчиг нэг мөрт. Өргөнд багтахгүй гарчиг эхлээд жигд жижгэрнэ
/// (1.0x хэмжээнээсээ доош орохгүй), тэгээд ч багтахгүй бол л "…"; 64px-д
/// өндрөөрөө багтахгүй бол гарчгийн блок бүхэлдээ жигд жижгэрнэ (overflow
/// гарахгүй). Брэнд нь лого тул текстийн масштабаар томрохгүй — Feed ба
/// Explore-ийн хооронд үсрэхгүй.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Tab-ын нүүрний толгой: зүүнд [NightOwlBrand] ([brandSize]), баруунд
  /// [actions]. Анхдагчаар Feed/Explore-ийн адил [NightOwlAtmosphere] гэрэлтэй.
  const AppHeader.brand({
    super.key,
    this.actions = const [],
    this.showDivider = false,
    this.atmosphere = true,
    this.backgroundColor,
    this.primary = true,
  })  : _variant = _AppHeaderVariant.brand,
        title = null,
        subtitle = null,
        subtitleColor = null,
        onBack = null,
        fallbackLocation = null,
        showBack = false,
        leading = null,
        compact = false,
        centerTitle = false,
        scrim = false,
        bottom = null;

  /// Дэд хуудасны толгой: буцах [GlassIconButton] ([AppIcons.back], "Буцах")
  /// + [title] ([AppTextStyles.pageTitle], [compact] бол [AppTextStyles.title])
  /// + сонголтоор [subtitle] + [actions].
  ///
  /// Буцах: [onBack] ?? (Navigator pop хийж чадвал `maybePop`, эс бөгөөс
  /// `GoRouter.go(fallbackLocation ?? AppRoutes.feed)`) — [goBack]-ийг үз.
  const AppHeader.title({
    super.key,
    required String this.title,
    this.subtitle,
    this.subtitleColor,
    this.onBack,
    this.fallbackLocation,
    this.showBack = true,
    this.leading,
    this.actions = const [],
    this.compact = false,
    this.centerTitle = false,
    this.showDivider = false,
    this.atmosphere = false,
    this.backgroundColor,
    this.bottom,
    this.primary = true,
  })  : _variant = _AppHeaderVariant.title,
        scrim = false;

  /// Зураг/видео дээрх толгой: тунгалаг дэвсгэр, буцах товч `onMedia`,
  /// гарчиг цагаан ([AppTextStyles.title], горимоос үл хамаарна).
  /// [actions]-д `GlassIconButton(onMedia: true, ...)` дамжуулна.
  /// Гэрэлтэй зураг дээр гарчиг/status bar уншигдахуйц байх хэрэгтэй бол
  /// [scrim] = true (дээрээс доош бараан градиент).
  const AppHeader.media({
    super.key,
    this.title,
    this.onBack,
    this.fallbackLocation,
    this.showBack = true,
    this.leading,
    this.actions = const [],
    this.centerTitle = false,
    this.scrim = false,
    this.primary = true,
  })  : _variant = _AppHeaderVariant.media,
        subtitle = null,
        subtitleColor = null,
        compact = true,
        showDivider = false,
        atmosphere = false,
        backgroundColor = null,
        bottom = null;

  /// Контентын өндөр (status bar-ыг оруулалгүй).
  static const double height = 64;

  /// Брэндийн НЭГ хэмжээ. Feed ба Explore хоёулаа өнөөдөр
  /// `NightOwlBrand(size: 28)` (mark 30px, "Night Owl" 21.8px) — 390px дээрх
  /// capture-аар хэмжээ нь ижил. Аудитын "18 ба 22 px" нь логоны ЗҮҮН ИРМЭГ
  /// (16 ба 20px gutter + зурган дахь 2px тунгалаг зах) байсан тул хэмжээг
  /// өөрчлөхгүй, байрлалыг нэг gutter-т нэгтгэв.
  static const double brandSize = 28;

  static const double _gutter = AppSpacing.page;

  /// [GlassIconButton]: 44px хүрэх талбар − 40px диск = тал бүрт 2px.
  static const double _hitInset = 2;

  /// Хүрэх талбараас гарчиг хүртэлх зай (дискээс 12px).
  static const double _gap = 10;

  /// Үйлдлийн хүрэх талбарууд хоорондын зай (дискүүд хооронд 8px).
  static const double _actionGap = 4;

  /// night_owl_mark.png-ийн зүүн тунгалаг зах: 1254px-ийн 90px (7.2%) — 30px
  /// mark дээр ≈2px. Шар шувууны ҮЗЭГДЭХ ирмэгийг gutter дээр буулгана.
  static const double _brandOpticalInset = 2;

  static const LinearGradient _scrimGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x73000000), Color(0x00000000)],
  );

  final _AppHeaderVariant _variant;

  /// Гарчиг ([AppHeader.title]-д заавал; хоосон бол харуулахгүй).
  final String? title;

  /// Гарчгийн доорх нэг мөр ([AppTextStyles.caption]). Жишээ: "12 пост".
  final String? subtitle;

  /// [subtitle]-ийн өнгийг дарж бичих (ж: шинэ зүйлд [AppColors.accentText]).
  final Color? subtitleColor;

  /// Буцах товчны үйлдлийг бүрэн солих (ж: хадгалаагүй өөрчлөлт асуух).
  final VoidCallback? onBack;

  /// Pop хийх хуудас байхгүй (deep link, refresh) үед очих зам.
  /// null бол [AppRoutes.feed].
  final String? fallbackLocation;

  /// Анхдагч буцах товчийг харуулах эсэх. Tab болон pushed хоёулаа болдог
  /// дэлгэцэд `showBack: ModalRoute.canPopOf(context) ?? false` (AppBar-ын
  /// дүрэм: зөвхөн доор нь хуудас байвал). `Navigator.of(context).canPop()`
  /// бүү хэрэглэ: root дээрх хуудсанд sheet/dialog нээлттэй үед true болно.
  final bool showBack;

  /// Буцах товчны оронд тавих өөр эхлэлийн widget (ж: профайлын "…" товч).
  /// Өгвөл [showBack], [onBack], [fallbackLocation]-ийг үл тооно.
  final Widget? leading;

  /// Баруун талын үйлдлүүд (ихэвчлэн [GlassIconButton]). Зайг толгой өөрөө нэмнэ.
  final List<Widget> actions;

  /// true бол гарчиг [AppTextStyles.title] (17) — нягт/хоёрдогч хуудсанд.
  final bool compact;

  /// Гарчгийг бүх өргөний төвд байрлуулах (буцах/үйлдэлтэй давхцахгүй).
  final bool centerTitle;

  /// Доод ирмэгт 1px hairline (Feed-ийн өнөөгийн хил: accentText 10%).
  final bool showDivider;

  /// [NightOwlAtmosphere] ягаан гэрэл (status bar-ын доогуур үргэлжилнэ).
  final bool atmosphere;

  /// Дэвсгэр өнгө. null бол тунгалаг (Scaffold-ийн bgBase харагдана).
  final Color? backgroundColor;

  /// [AppHeader.media]: дээрээс доош бараан градиент (гарчиг, status bar
  /// уншигдахуйц). Бусад хувилбарт үргэлж false.
  final bool scrim;

  /// 64px мөрийн доор (ж: TabBar). [preferredSize]-д тооцогдоно.
  final PreferredSizeWidget? bottom;

  /// true бол дээд status bar-ын зайг толгой өөрөө авна (дээрх тайлбарыг үз).
  final bool primary;

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  /// Апп даяарх буцах дүрэм: энэ хуудсыг агуулсан Navigator pop хийж чадвал
  /// `maybePop` (PopScope-ийг хүндэтгэнэ), чадахгүй бол (deep link, refresh)
  /// `GoRouter.go(fallbackLocation ?? AppRoutes.feed)`.
  /// Өөрийн [onBack]-тай дэлгэцүүд (ж: ачаалж байх үед буцахыг хориглох)
  /// ч энэ дүрмийг дахин ашиглана.
  static void goBack(BuildContext context, {String? fallbackLocation}) {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    GoRouter.maybeOf(context)?.go(fallbackLocation ?? AppRoutes.feed);
  }

  @override
  Widget build(BuildContext context) {
    final isBrand = _variant == _AppHeaderVariant.brand;
    final isMedia = _variant == _AppHeaderVariant.media;
    final Widget? lead = isBrand
        ? null
        : leading ??
            (showBack
                ? GlassIconButton(
                    icon: AppIcons.back,
                    iconSize: 24,
                    tooltip: 'Буцах',
                    onMedia: isMedia,
                    onTap: onBack ??
                        (() => goBack(context,
                            fallbackLocation: fallbackLocation)),
                  )
                : null);
    final heading = title;
    final Widget? middle = isBrand
        ? _brand()
        : heading != null && heading.isNotEmpty
            ? _HeaderTitle(
                title: heading,
                style: _titleStyle(isMedia),
                subtitle: subtitle,
                subtitleStyle: subtitleColor == null
                    ? AppTextStyles.caption
                    : AppTextStyles.caption.copyWith(color: subtitleColor),
                center: centerTitle,
              )
            : null;
    final hasActions = actions.isNotEmpty;

    // NavigationToolbar нь гарчгийн хоёр талд [_gap] зай тавьдаг тул padding-ийг
    // түүнд тааруулж: хүрэх талбар 18px-ээс, гарчиг/брэнд 20px-ээс эхэлнэ.
    final start = lead != null
        ? _gutter - _hitInset
        : _gutter - _gap - (isBrand ? _brandOpticalInset : 0.0);
    final end = hasActions ? _gutter - _hitInset : _gutter - _gap;

    Widget bar = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: start, end: end),
        child: NavigationToolbar(
          // Leading-ийг toolbar 64px өндөрт тулгадаг — 44px товчийг төвд нь.
          leading: lead == null ? null : Align(widthFactor: 1, child: lead),
          middle: middle,
          trailing: hasActions
              ? Row(mainAxisSize: MainAxisSize.min, children: _spacedActions())
              : null,
          centerMiddle: centerTitle,
          middleSpacing: _gap,
        ),
      ),
    );
    final below = bottom;
    if (below != null) {
      bar = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [bar, below]);
    }
    if (primary) bar = SafeArea(bottom: false, child: bar);
    if (scrim) {
      bar = DecoratedBox(
          decoration: const BoxDecoration(gradient: _scrimGradient),
          child: bar);
    }
    if (atmosphere) bar = NightOwlAtmosphere(child: bar);
    final background = backgroundColor;
    if (background != null) bar = ColoredBox(color: background, child: bar);
    if (showDivider) {
      bar = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: AppColors.accentText.withValues(alpha: .10)))),
        child: bar,
      );
    }
    // AppBar-тай ижил: толгой нэг container, гарчиг ба товч бүр тусдаа node.
    return Semantics(container: true, explicitChildNodes: true, child: bar);
  }

  List<Widget> _spacedActions() => [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: _actionGap),
          actions[i],
        ],
      ];

  TextStyle _titleStyle(bool media) {
    if (media) {
      // Үргэлж бараан медиа дээр — горимоос үл хамааран цайвар, зөөлөн сүүдэртэй.
      return AppTextStyles.title.copyWith(
        color: AppColors.textPrimaryDark,
        shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)],
      );
    }
    return compact ? AppTextStyles.title : AppTextStyles.pageTitle;
  }

  /// Лого нь текст биш дүрс тул текстийн масштабаар томрохгүй; зай хүрэлцэхгүй
  /// (320px + 3 үйлдэл) үед л жигд жижгэрнэ.
  static Widget _brand() => MediaQuery.withNoTextScaling(
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: NightOwlBrand(size: brandSize),
        ),
      );
}

/// Нэг мөрт гарчиг (+ дэд мөр). Том текстэд slot-д өргөнөөрөө багтахгүй
/// гарчиг эхлээд жигд жижгэрнэ, гэхдээ 1.0x хэмжээнээсээ доош биш; түүнээс ч
/// урт бол "…". Өндөр нь 64px-д багтахгүй бол блок бүхэлдээ жигд жижгэрнэ.
/// Дэд мөр slot-оос өргөсөхгүй тул гарчгийг өөрөө жижигрүүлэхгүй.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({
    required this.title,
    required this.style,
    required this.center,
    this.subtitle,
    this.subtitleStyle,
  });

  final String title;
  final TextStyle style;
  final bool center;
  final String? subtitle;
  final TextStyle? subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    final sub = subtitle;
    // Текстийн масштаб (≥ 1). Гарчиг slot-оос ийм дахин өргөн байж болно:
    // FittedBox түүнийг slot-д жижигрүүлэхэд 1.0x хэмжээнээс доош орохгүй.
    final double fontSize = style.fontSize ?? 17;
    final grow = math.max(
        1.0, MediaQuery.textScalerOf(context).scale(fontSize) / fontSize);
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: center ? Alignment.center : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * grow),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: align,
                    style: style),
              ),
              if (sub != null && sub.isNotEmpty)
                // Slot-ын өргөнд "…" болно: урт дэд мөр гарчгийг жижигрүүлэхгүй.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: align,
                      style: subtitleStyle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
