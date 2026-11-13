import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_icons.dart';
import 'app_radii.dart';
import 'app_text_styles.dart';

class AppTheme {
  static ThemeData get dark => _buildTheme(isDark: true);
  static ThemeData get light => _buildTheme(isDark: false);

  static ThemeData _buildTheme({required bool isDark}) {
    // Өнгийг ЗӨВХӨН isDark-аас гаргана (AppColors.isDarkMode-оос биш):
    // MaterialApp theme ба darkTheme хоёрыг зэрэг барьдаг тул глобал туг
    // аль нэгэнд нь буруу байх болно.
    final bg       = isDark ? AppColors.bgBaseDark      : AppColors.bgBaseLight;
    final elevated = isDark ? AppColors.bgElevatedDark  : AppColors.bgElevatedLight;
    final surface  = isDark ? AppColors.bgSurfaceDark   : AppColors.bgSurfaceLight;
    final textPri  = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSec  = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final textTer  = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final hairline = isDark ? AppColors.hairlineDark    : AppColors.hairlineLight;
    final hairline2 = isDark ? AppColors.hairline2Dark  : AppColors.hairline2Light;
    // Текст, icon, фокусын accent (= AppColors.accentText): Night #B6A4FF,
    // Day #6550AD. Хуучин `accentLink`-ийг үүгээр нэгтгэв.
    final accentText =
        isDark ? AppColors.accentTextDark : AppColors.accentTextLight;
    // Алдааны текст ба icon (= AppColors.danger): Night #FF4566, Day #C81E3A.
    final danger = isDark ? AppColors.dangerDark : AppColors.dangerLight;
    // Брэндийн violet FILL — дээр нь зөвхөн цагаан текст/icon (5.2:1).
    const fill = AppColors.accentStart;
    const onFill = Colors.white;
    // Тод accent (Night-д цайвар, Day-д бараан) fill дээрх агуулгын өнгө.
    final onAccent = isDark ? AppColors.bgBaseDark : Colors.white;
    // Tooltip ба M3-ийн inverse гадаргуу — горимын эсрэг өнгө.
    final inverseSurface = textPri;
    final onInverseSurface =
        isDark ? AppColors.bgElevatedDark : AppColors.textPrimaryDark;

    final colorScheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      // primary = текст/icon-ы accent (M3-ийн content өнгө). Theme-гүй
      // Material хэсгүүд (cursor, refresh, сонгосон төлөв) уншигдахуйц болно.
      // #7654D6-ыг текстэд ашиглахаа больсон (DS-01).
      primary: accentText,
      onPrimary: onAccent,
      // Брэндийн violet fill + цагаан: tonal товч, чип, time picker.
      primaryContainer: fill,
      onPrimaryContainer: onFill,
      secondary: isDark ? AppColors.magenta : AppColors.steel,
      onSecondary: onAccent,
      secondaryContainer: fill,
      onSecondaryContainer: onFill,
      tertiary: isDark ? AppColors.limeDark : AppColors.limeLight,
      onTertiary: onAccent,
      error: danger,
      onError: onAccent,
      errorContainer: Color.alphaBlend(
          danger.withValues(alpha: isDark ? 0.18 : 0.12), elevated),
      onErrorContainer: isDark ? Color.lerp(danger, Colors.white, 0.6) : danger,
      surface: surface,
      onSurface: textPri,
      onSurfaceVariant: textSec,
      // Гадаргуугийн шат — bgBase / bgElevated / bgSurface гэр бүл.
      surfaceDim: isDark
          ? bg
          : Color.alphaBlend(
              AppColors.textPrimaryLight.withValues(alpha: 0.08), surface),
      surfaceBright: isDark
          ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), surface)
          : elevated,
      surfaceContainerLowest: isDark ? bg : elevated,
      surfaceContainerLow: isDark ? elevated : bg,
      surfaceContainer: Color.lerp(isDark ? elevated : bg, surface, 0.5),
      surfaceContainerHigh: surface,
      surfaceContainerHighest: Color.alphaBlend(
          (isDark ? Colors.white : AppColors.textPrimaryLight)
              .withValues(alpha: 0.05),
          surface),
      outline: textTer,
      outlineVariant: hairline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: inverseSurface,
      onInverseSurface: onInverseSurface,
      inversePrimary:
          isDark ? AppColors.accentTextLight : AppColors.accentTextDark,
      // Material 3-ийн elevation-д violet туяа нэмдэггүй.
      surfaceTint: Colors.transparent,
    );

    // AppTextStyles токенуудыг Material-ийн textTheme рүү буулгав —
    // ингэснээр загварлаагүй Material widget-үүд ч апп-ын хэмжээст ордог.
    // Өнгийг тухайн горимын дагуу шууд өгнө (dyn* getter build үеийн
    // горимоос хамаардаг тул энд найдвартай биш). Бүх style нэг 'Inter'
    // family-тай тул өвлөсөн style дээр жин нэмэхэд жинхэнэ тод файл сонгогдоно.
    final textTheme = (isDark ? ThemeData.dark() : ThemeData.light())
        .textTheme
        .apply(
          fontFamily: AppTextStyles.fontFamily,
          bodyColor: textPri,
          displayColor: textPri,
        )
        .copyWith(
          displayLarge:  AppTextStyles.displayLg.copyWith(color: textPri),
          displayMedium: AppTextStyles.displayMd.copyWith(color: textPri),
          displaySmall:  AppTextStyles.displaySm.copyWith(color: textPri),
          headlineSmall: AppTextStyles.h1.copyWith(color: textPri),
          titleLarge:    AppTextStyles.h2.copyWith(color: textPri),
          titleMedium:   AppTextStyles.h3.copyWith(color: textPri),
          bodyLarge:     AppTextStyles.bodyLg.copyWith(color: textPri),
          bodyMedium:    AppTextStyles.bodyMd.copyWith(color: textPri),
          bodySmall:     AppTextStyles.bodySm.copyWith(color: textSec),
          labelLarge:    AppTextStyles.labelLg.copyWith(color: textPri),
          labelMedium:   AppTextStyles.labelMd.copyWith(color: textPri),
          labelSmall:    AppTextStyles.labelSm.copyWith(color: textSec),
        );

    // Popup / dropdown цэсний нэг загвар: elevated дэвсгэр, hairline хүрээ.
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(elevated),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(BorderSide(color: hairline)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: AppRadii.mdR),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      // pubspec.yaml-ийн Inter family (5 жин) — google_fonts-гүй.
      fontFamily: AppTextStyles.fontFamily,
      scaffoldBackgroundColor: bg,
      // DataTable, ExpansionTile г.м. dividerTheme-гүй хэсэг ч hairline.
      dividerColor: hairline,
      colorScheme: colorScheme,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPri,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        centerTitle: false,
        titleTextStyle: AppTextStyles.title.copyWith(color: textPri),
      ),
      // Далд BackButton (LicensePage г.м.) ч апп-ын НЭГ буцах glyph-ийг
      // хэрэглэнэ (DS-06/DS-09), платформын arrow_back биш.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(AppIcons.back),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: elevated,
        selectedItemColor: accentText,
        unselectedItemColor: textSec,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        // Premium glass card — slightly tighter radius, deeper separation
        color: elevated,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lgR,
          side: BorderSide(color: hairline, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Шилэн талбар — dark горимд бага зэрэг тунгалаг
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: AppRadii.mdR,
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdR,
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdR,
          borderSide: BorderSide(color: accentText, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdR,
          borderSide: BorderSide(color: danger.withValues(alpha: 0.6)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdR,
          borderSide: BorderSide(color: danger, width: 1.4),
        ),
        hintStyle: TextStyle(color: textSec.withValues(alpha: 0.8), fontSize: 14),
        labelStyle: TextStyle(color: textSec, fontSize: 14),
        // Дээш хөвсөн шошго: фокуслахад accent, алдаатай үед danger.
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          final Color color;
          if (states.contains(WidgetState.error)) {
            color = danger;
          } else if (states.contains(WidgetState.focused)) {
            color = accentText;
          } else if (states.contains(WidgetState.disabled)) {
            color = textTer;
          } else {
            color = textSec;
          }
          return TextStyle(color: color, fontSize: 14);
        }),
        errorStyle: TextStyle(color: danger, fontSize: 12),
        prefixIconColor: textSec,
        suffixIconColor: textSec,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // ─── FilledButton — theme-гүй үед M3-ийн 40px товч болдог байв.
      // Одоо брэндийн violet pill, 48px өндөр (өргөн нь агуулгаараа).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: onFill,
          // Идэвхгүй үед GradientButton шиг: гадаргуу + бүдэг бичиг.
          disabledBackgroundColor: surface,
          disabledForegroundColor: textTer,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: AppTextStyles.btn.copyWith(color: onFill),
          shape: const StadiumBorder(),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return textTer.withValues(alpha: 0.35);
            }
            return AppColors.accentStart;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            return AppColors.accentEnd.withValues(alpha: 0.18);
          }),
          minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          // Primary товч ба чип бүгд pill хэлбэртэй (эзэмшигчийн шийдвэр).
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(textPri),
          side: WidgetStatePropertyAll(BorderSide(color: hairline, width: 1)),
          minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: textPri, size: 24),
      // Сонгогдсон ListTile (жишээ нь venue picker) бүдэг #7654D6 биш,
      // текстэд зориулсан accent-аар харагдана. textColor-ийг ЗОРИУДААР
      // өгөөгүй: ListTile үүнийг subtitle-д ч хэрэглэж гарчигтай ижил тод
      // болгодог. Оронд нь гарчиг/subtitle-ийн style-д өнгө өгөв.
      listTileTheme: ListTileThemeData(
        selectedColor: accentText,
        iconColor: textSec,
        titleTextStyle: AppTextStyles.bodyLg.copyWith(color: textPri),
        subtitleTextStyle: AppTextStyles.bodyMd.copyWith(color: textSec),
        selectedTileColor: fill.withValues(alpha: 0.12),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: textPri,
        unselectedLabelColor: textSec,
        indicatorColor: accentText,
        dividerColor: hairline,
        labelStyle: AppTextStyles.labelLg.copyWith(color: textPri),
        unselectedLabelStyle: AppTextStyles.labelLg.copyWith(color: textSec),
      ),
      // ─── Чип — pill, hairline хүрээ, check тэмдэггүй. Сонгогдсон чип
      // violet fill + цагаан бичиг.
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: hairline2),
        backgroundColor: surface,
        selectedColor: fill,
        // M3 chip сонгогдсон бичгийн өнгийг labelStyle-ийн төлвөөс авдаг
        // (secondaryLabelStyle-ийг үл тоомсорлоно) тул өнгийг төлвөөр өгнө.
        labelStyle: AppTextStyles.labelMd.copyWith(
          color: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return onFill;
            if (states.contains(WidgetState.disabled)) return textTer;
            return textPri;
          }),
        ),
        secondaryLabelStyle: AppTextStyles.labelMd.copyWith(color: onFill),
        showCheckmark: false,
        checkmarkColor: onFill,
        // Material-ийн 8px label padding-тай нийлээд хажуудаа ~16px.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentText,
        linearTrackColor: hairline2,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return selected ? elevated : textPri.withValues(alpha: 0.38);
          }
          return selected ? onFill : textSec;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return selected ? textPri.withValues(alpha: 0.12) : surface;
          }
          return selected ? fill : surface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return states.contains(WidgetState.disabled) ? hairline : hairline2;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.selected)) return Colors.transparent;
          if (states.contains(WidgetState.disabled)) {
            return textPri.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.error)) return AppColors.dangerFill;
          return fill;
        }),
        checkColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ? elevated : onFill),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return textPri.withValues(alpha: 0.38);
          }
          return states.contains(WidgetState.selected) ? accentText : textSec;
        }),
      ),
      // ─── Цэснүүд — 4px булантай саарал M3 popup биш, апп-ын карт шиг.
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdR,
          side: BorderSide(color: hairline),
        ),
        textStyle: AppTextStyles.bodyMd.copyWith(color: textPri),
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            AppTextStyles.bodyMd.copyWith(
                color: states.contains(WidgetState.disabled)
                    ? textTer
                    : textPri)),
        iconColor: textSec,
      ),
      menuTheme: MenuThemeData(style: menuStyle),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppTextStyles.bodyMd.copyWith(color: textPri),
        menuStyle: menuStyle,
      ),
      // ─── Огноо/цаг сонгогч — монгол locale апп даяар тохируулсан.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.xlR,
          side: BorderSide(color: hairline),
        ),
        headerHeadlineStyle: AppTextStyles.h1.copyWith(color: textPri),
        headerHelpStyle: AppTextStyles.labelLg.copyWith(color: textSec),
        weekdayStyle: AppTextStyles.labelMd.copyWith(color: textSec),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onFill : null),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? fill : null),
        todayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onFill;
          if (states.contains(WidgetState.disabled)) {
            return accentText.withValues(alpha: 0.38);
          }
          return accentText;
        }),
        todayBackgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? fill : null),
        todayBorder: BorderSide(color: accentText),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onFill : null),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? fill : null),
        rangeSelectionBackgroundColor: fill.withValues(alpha: 0.24),
        dividerColor: hairline,
        subHeaderForegroundColor: textSec,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: elevated,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.xlR,
          side: BorderSide(color: hairline),
        ),
        hourMinuteColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? fill : surface),
        hourMinuteTextColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onFill : textPri),
        dayPeriodColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? fill : Colors.transparent),
        dayPeriodTextColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onFill : textSec),
        dayPeriodBorderSide: BorderSide(color: hairline2),
        dialBackgroundColor: surface,
        dialHandColor: fill,
        dialTextColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? onFill : textPri),
        entryModeIconColor: textSec,
        helpTextStyle: AppTextStyles.labelMd.copyWith(color: textSec),
      ),
      // ─── Тоот тэмдэг — 9px бүдэг улаан биш, цагаан бичигтэй dangerFill.
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.dangerFill,
        textColor: Colors.white,
        smallSize: 8,
        largeSize: 16,
        textStyle: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: inverseSurface,
          borderRadius: AppRadii.smR,
        ),
        textStyle: AppTextStyles.caption.copyWith(color: onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: fill,
        inactiveTrackColor: hairline2,
        thumbColor: accentText,
        overlayColor: accentText.withValues(alpha: 0.12),
        valueIndicatorColor: fill,
        valueIndicatorTextStyle: AppTextStyles.labelMd.copyWith(color: onFill),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: textPri,
          selectedForegroundColor: onFill,
          selectedBackgroundColor: fill,
          side: BorderSide(color: hairline2),
          shape: const StadiumBorder(),
          textStyle: AppTextStyles.labelLg.copyWith(color: textPri),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        // Glass dark — хөвөгч, hairline хүрээтэй, радиус 14
        backgroundColor: isDark ? const Color(0xF0121218) : elevated,
        contentTextStyle: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: textPri,
            fontSize: 14, fontWeight: FontWeight.w500),
        actionTextColor: accentText,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdR,
          side: BorderSide(color: hairline),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      // ─── Доод sheet — 23 дуудалт гар аргаар өнгө/радиус дамжуулж
      // (заримд 28, заримд 20) байсныг энд нэг мөр болгов.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: elevated,
        modalBackgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: hairline2,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      // ─── Диалог — 12 AlertDialog гар аргаар өнгө/хэлбэр өгдөг байсан ───
      dialogTheme: DialogThemeData(
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lgR,
          side: BorderSide(color: hairline, width: 1),
        ),
        // Sheet-ийн гарчигтай ижил `title` (17/w700) — бүх dialog нэг хэмжээтэй.
        titleTextStyle: AppTextStyles.title.copyWith(color: textPri),
        contentTextStyle: AppTextStyles.bodyMd.copyWith(color: textSec),
      ),
      // ─── TextButton — 36-аас 33 нь загваргүй байсан тул M3-ийн ягаан
      // өнгө, 40px өндөртэй унадаг байв. Одоо accentText + 44px хүрэлцэхүйц,
      // дарахад pill хэлбэрийн долгион.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentText,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: AppTextStyles.btn.copyWith(color: accentText),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}
