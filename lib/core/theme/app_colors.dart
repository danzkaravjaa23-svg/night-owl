import 'package:flutter/material.dart';

/// NightOwl UB — Design tokens
/// "FUTURIST NIGHTSCAPE" — neon палитр.
/// ⚠️ Token НЭРС хэвээр (бүх дэлгэц эдгээрийг уншдаг) — зөвхөн УТГА нь neon болсон.
abstract class AppColors {
  // ─── Deep void (dark theme, default) ───
  static const Color bgBase      = Color(0xFF050505); // void black
  static const Color bgElevated  = Color(0xFF0D0D12);
  static const Color bgSurface   = Color(0xFF15151C);
  static const Color bgOverlay   = Color(0xC0050505); // rgba(5,5,5,0.75)

  // Borders — ultra-thin glass hairline
  static const Color hairline    = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
  static const Color hairline2   = Color(0x26FFFFFF); // rgba(255,255,255,0.15)

  // Text — cool white / steel
  static const Color textPrimary   = Color(0xFFF4F6FA);
  static const Color textSecondary = Color(0xFFA7ADBA);
  // WCAG AA (4.5:1) хангахаар цайруулсан — 10–11px жижиг шошгонд уншигдана.
  static const Color textTertiary  = Color(0xFF7E8494);
  static const Color textMono      = Color(0xFF9FB6C2);

  // ─── Electric cyan (active / selected / focus — "silver" нэрээр) ───
  // Хуучин "silver" токенуудыг neon cyan болгосон тул nav-active, брэнд гялбаа cyan болно.
  static const Color silver      = Color(0xFF22E7FF); // neon cyan (active)
  static const Color silverLight = Color(0xFFBDF6FF);
  static const Color silverDark  = Color(0xFF15C2DA);
  static const Color steel       = Color(0xFF0E7F90); // deep cyan

  // Дөт хандалт (шинэ alias — нэмэлт, аюулгүй)
  static const Color neonCyan = Color(0xFF22E7FF);
  static const Color magenta  = Color(0xFFE935C8);
  static const Color lime     = Color(0xFFB4FF2E);
  static const Color amber    = Color(0xFFFFB020);
  static const Color orange   = Color(0xFFFF6A2B);

  // ─── Primary accent (magenta/purple — primary action, like, badge, pin) ───
  // Цагаан текст уншигдахуйц гүн magenta-purple.
  static const Color accentStart  = Color(0xFFC026D3); // vivid magenta (primary/solid)
  static const Color accentMid    = Color(0xFF9333EA); // purple (gradient mid)
  static const Color accentEnd    = Color(0xFFFF2D8E); // pink (gradient end)
  static const Color accentPurple = Color(0xFF7C3AED); // purple

  // ─── Үйлдлийн семантик өнгө — апп даяар НЭГ өнгө ───
  // (Өмнө нь feed / reels / story viewer гурав өөр өнгөөр зүрх будаж байсан.)
  static const Color like  = accentEnd;    // зүрх — дарсан үе
  static const Color saved = accentStart;  // хадгалсан тэмдэг

  // Status
  static const Color success = Color(0xFFB4FF2E); // glowing lime (live/active)
  static const Color error   = Color(0xFFFF4566);
  static const Color warning = Color(0xFFFFB020); // amber

  // ─── Light theme ───
  static const Color bgBaseLight      = Color(0xFFFAF6EE);
  static const Color bgElevatedLight  = Color(0xFFFFFFFF);
  static const Color bgSurfaceLight   = Color(0xFFF3ECDF);

  static const Color hairlineLight    = Color(0x141A0B2E);
  static const Color hairline2Light   = Color(0x291A0B2E);

  static const Color textPrimaryLight   = Color(0xFF13031F);
  static const Color textSecondaryLight = Color(0xFF5C4A82);
  // Цайвар дэвсгэр дээр AA хангахаар бараантуулсан.
  static const Color textTertiaryLight  = Color(0xFF6F6390);

  // ─── Theme-aware (динамик) резолюц ───
  // ThemeModeNotifier горим солигдоход энэ флагийг шинэчилдэг;
  // MaterialApp бүх мод-оо дахин build хийдэг тул getter-ууд шинэ утга буцаана.
  // const токенууд хэвээр (дээрх) — эдгээр нь НЭМЭЛТ, light горимд зөв өнгө өгнө.
  static bool isDarkMode = true;
  static Color get dynBgBase        => isDarkMode ? bgBase        : bgBaseLight;
  static Color get dynBgElevated    => isDarkMode ? bgElevated    : bgElevatedLight;
  static Color get dynBgSurface     => isDarkMode ? bgSurface     : bgSurfaceLight;
  static Color get dynHairline      => isDarkMode ? hairline      : hairlineLight;
  static Color get dynHairline2     => isDarkMode ? hairline2     : hairline2Light;
  static Color get dynTextPrimary   => isDarkMode ? textPrimary   : textPrimaryLight;
  static Color get dynTextSecondary => isDarkMode ? textSecondary : textSecondaryLight;
  static Color get dynTextTertiary  => isDarkMode ? textTertiary  : textTertiaryLight;
  static Color get dynTextMono      => isDarkMode ? textMono      : textSecondaryLight;

  // ─── Primary action gradient — magenta → purple → pink ───
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFC026D3), Color(0xFFFF2D8E)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient accentGradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x55C026D3), Color(0x337C3AED)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFC026D3), accentEnd],
  );

  // ─── Cyan glow gradient ("chrome" нэрээр — nav active / брэнд гялбаа) ───
  static const LinearGradient chromeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [silverLight, silver, steel, silver],
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
    colors: [Color(0x4022E7FF), Colors.transparent],
  );

  // ─── Story ring — magenta → pink → cyan люкс sweep ───
  // Эхлэл/төгсгөл ижил өнгө тул эргэлт залгаасгүй, тасралтгүй харагдана.
  static const SweepGradient storyRingGradient = SweepGradient(
    transform: GradientRotation(-1.5708), // дээд цэгээс эхэлнэ
    colors: [magenta, accentEnd, Color(0xFFFF6FB3), neonCyan, accentPurple, magenta],
    stops: [0.0, 0.25, 0.45, 0.65, 0.85, 1.0],
  );

  // ─── Неон glow сүүдэр — CTA/идэвхтэй элементэд нэг мөрөөр ───
  static List<BoxShadow> glowShadow(Color color,
      {double alpha = 0.35, double blur = 22, double spread = -2,
      Offset offset = const Offset(0, 6)}) => [
    BoxShadow(color: color.withValues(alpha: alpha),
        blurRadius: blur, spreadRadius: spread, offset: offset),
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
