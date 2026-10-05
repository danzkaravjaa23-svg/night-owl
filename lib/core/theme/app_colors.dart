import 'package:flutter/material.dart';

/// NightOwl UB — Design tokens
/// Midnight violet palette shared by every app surface.
/// ⚠️ Token НЭРС хэвээр (бүх дэлгэц эдгээрийг уншдаг) — зөвхөн УТГА нь neon болсон.
abstract class AppColors {
  // ─── Deep void (dark theme, default) ───
  static const Color bgBaseDark = Color(0xFF0B0D17); // void black
  static Color get bgBase => isDarkMode ? bgBaseDark : bgBaseLight;
  static const Color bgElevatedDark = Color(0xFF121625);
  static Color get bgElevated => isDarkMode ? bgElevatedDark : bgElevatedLight;
  static const Color bgSurfaceDark = Color(0xFF1B2033);
  static Color get bgSurface => isDarkMode ? bgSurfaceDark : bgSurfaceLight;
  static const Color bgOverlay = Color(0xC00B0D17); // rgba(5,5,5,0.75)

  // Borders — ultra-thin glass hairline
  static const Color hairlineDark = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
  static Color get hairline => isDarkMode ? hairlineDark : hairlineLight;
  static const Color hairline2Dark =
      Color(0x26FFFFFF); // rgba(255,255,255,0.15)
  static Color get hairline2 => isDarkMode ? hairline2Dark : hairline2Light;

  // Text — cool white / steel
  static const Color textPrimaryDark = Color(0xFFF5F5FC);
  static Color get textPrimary =>
      isDarkMode ? textPrimaryDark : textPrimaryLight;
  static const Color textSecondaryDark = Color(0xFFB2B8CE);
  static Color get textSecondary =>
      isDarkMode ? textSecondaryDark : textSecondaryLight;
  // WCAG AA (4.5:1) хангахаар цайруулсан — 10–11px жижиг шошгонд уншигдана.
  static const Color textTertiaryDark = Color(0xFF8993AE);
  static Color get textTertiary =>
      isDarkMode ? textTertiaryDark : textTertiaryLight;
  static const Color textMonoDark = Color(0xFF9FB6C2);
  static Color get textMono => isDarkMode ? textMonoDark : textSecondaryLight;

  // ─── Electric cyan (active / selected / focus — "silver" нэрээр) ───
  // Хуучин "silver" токенуудыг neon cyan болгосон тул nav-active, брэнд гялбаа cyan болно.
  static const Color silverNeon = Color(0xFFB6A4FF); // neon cyan (active)
  static Color get silver => isDarkMode ? silverNeon : neonCyanLight;
  static const Color silverLight = Color(0xFFE4DCFF);
  static const Color silverDark = Color(0xFF9680EA);
  static const Color steel = Color(0xFF6350AC); // deep cyan

  // Дөт хандалт (шинэ alias — нэмэлт, аюулгүй)
  static const Color neonCyanDark = Color(0xFFB6A4FF);
  static const Color neonCyanLight =
      Color(0xFF6550AD); // цайвар дэвсгэр дээр AA
  static Color get neonCyan => isDarkMode ? neonCyanDark : neonCyanLight;
  static const Color magenta = Color(0xFFA78BFA);
  static const Color limeDark = Color(0xFF6EE7B7);
  static const Color limeLight = Color(0xFF17734F); // цайвар дэвсгэр дээр AA
  static Color get lime => isDarkMode ? limeDark : limeLight;
  static const Color amber = Color(0xFFFFB020);
  static const Color orange = Color(0xFFFF6A2B);

  // ─── Primary accent (magenta/purple — primary action, like, badge, pin) ───
  // Цагаан текст уншигдахуйц гүн magenta-purple.
  static const Color accentStart =
      Color(0xFF7654D6); // vivid magenta (primary/solid)
  static const Color accentMid = Color(0xFF6944C6); // purple (gradient mid)
  static const Color accentEnd = Color(0xFF6745C1); // pink (gradient end)
  static const Color accentPurple =
      Color(0xFF7654D6); // selected reference violet

  // ─── Үйлдлийн семантик өнгө — апп даяар НЭГ өнгө ───
  // (Өмнө нь feed / reels / story viewer гурав өөр өнгөөр зүрх будаж байсан.)
  static const Color like = accentEnd; // зүрх — дарсан үе
  static const Color saved = accentStart; // хадгалсан тэмдэг

  // Status
  static const Color successDark =
      Color(0xFF6EE7B7); // glowing lime (live/active)
  static const Color successLight = Color(0xFF17734F); // цайвар дэвсгэр дээр AA
  static Color get success => isDarkMode ? successDark : successLight;
  static const Color error = Color(0xFFFF4566);
  static const Color warning = Color(0xFFFFB020); // amber

  // ─── Light theme ───
  static const Color bgBaseLight = Color(0xFFF5F4FA);
  static const Color bgElevatedLight = Color(0xFFFFFFFF);
  static const Color bgSurfaceLight = Color(0xFFEDEBF5);

  static const Color hairlineLight = Color(0x141A0B2E);
  static const Color hairline2Light = Color(0x291A0B2E);

  static const Color textPrimaryLight = Color(0xFF19172B);
  static const Color textSecondaryLight = Color(0xFF57536D);
  // Цайвар дэвсгэр дээр AA хангахаар бараантуулсан.
  static const Color textTertiaryLight = Color(0xFF6C6680);

  // ─── Theme-aware (динамик) резолюц ───
  // ThemeModeNotifier горим солигдоход энэ флагийг шинэчилдэг;
  // MaterialApp бүх мод-оо дахин build хийдэг тул getter-ууд шинэ утга буцаана.
  // Саармаг токенууд (bg*, hairline*, text*) болон neonCyan/silver/lime/success
  // одоо өөрсдөө адаптив getter. dyn* нь хуучин кодын alias.
  // Горимоос үл хамааран ҮРГЭЛЖ харанхуй байх гадаргуу (reels, story, live,
  // видео/зураг дээрх overlay) *Dark const-уудыг ашиглана.
  static bool isDarkMode = true;
  static Color get dynBgBase => bgBase;
  static Color get dynBgElevated => bgElevated;
  static Color get dynBgSurface => bgSurface;
  static Color get dynHairline => hairline;
  static Color get dynHairline2 => hairline2;
  static Color get dynTextPrimary => textPrimary;
  static Color get dynTextSecondary => textSecondary;
  static Color get dynTextTertiary => textTertiary;
  static Color get dynTextMono => textMono;

  /// Үргэлж харанхуй гадаргуу (reels, story, live, видео, splash) дээр
  /// адаптив өнгийг харанхуй хувилбараар нь солино. Бусад өнгө хэвээр.
  /// Харанхуй горимд аль хэдийн харанхуй утгатай тул өөрчлөлтгүй.
  static Color? toDark(Color? c) => c == null ? null : (_toDarkMap[c] ?? c);

  static final Map<Color, Color> _toDarkMap = {
    bgBaseLight: bgBaseDark,
    bgElevatedLight: bgElevatedDark,
    bgSurfaceLight: bgSurfaceDark,
    hairlineLight: hairlineDark,
    hairline2Light: hairline2Dark,
    textPrimaryLight: textPrimaryDark,
    textSecondaryLight: textSecondaryDark,
    textTertiaryLight: textTertiaryDark,
    neonCyanLight: neonCyanDark,
    limeLight: limeDark,
  };

  // ─── Primary action gradient — magenta → purple → pink ───
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7654D6), Color(0xFF6944C6), Color(0xFF6745C1)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient accentGradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x557654D6), Color(0x336745C1)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6745C1), Color(0xFF7654D6), accentEnd],
  );

  // ─── Cyan glow gradient ("chrome" нэрээр — nav active / брэнд гялбаа) ───
  static const LinearGradient chromeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [silverLight, silverNeon, steel, silverNeon],
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  static const LinearGradient silverGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [silverLight, silverDark],
  );

  // Aurora background glow — neon cyan/magenta
  static const RadialGradient auroraGradient = RadialGradient(
    center: Alignment(-0.6, -0.6),
    radius: 1.2,
    colors: [Color(0x40B6A4FF), Colors.transparent],
  );

  // ─── Story ring — magenta → pink → cyan люкс sweep ───
  // Эхлэл/төгсгөл ижил өнгө тул эргэлт залгаасгүй, тасралтгүй харагдана.
  static const SweepGradient storyRingGradient = SweepGradient(
    transform: GradientRotation(-1.5708), // дээд цэгээс эхэлнэ
    colors: [accentStart, silverDark, silverNeon, accentStart],
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  // ─── Неон glow сүүдэр — CTA/идэвхтэй элементэд нэг мөрөөр ───
  static List<BoxShadow> glowShadow(Color color,
          {double alpha = 0.16,
          double blur = 18,
          double spread = -2,
          Offset offset = const Offset(0, 6)}) =>
      [
        BoxShadow(
            color: color.withValues(alpha: alpha),
            blurRadius: blur,
            spreadRadius: spread,
            offset: offset),
      ];

  // ─── Давхарласан сүүдэр пресетүүд — glass элемент агаарт хөвөх мэдрэмж ───
  // Карт: ойрын нягт + холын зөөлөн сүүдэр
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
  // Хөвөгч док/шилэн бар — илүү гүн, өргөн сүүдэр
  static const List<BoxShadow> shadowDock = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 30, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3)),
  ];
}
