import 'package:flutter/material.dart';

/// NightOwl UB — Design tokens
/// Дизайн токенүүд — styles.css-с шууд хөрвүүлсэн
abstract class AppColors {
  // ─── Dark theme (default) — Liquid Chrome Disco ───
  // Disco owl logo шиг цэвэр хар + графит ертөнц
  static const Color bgBase      = Color(0xFF050507);
  static const Color bgElevated  = Color(0xFF101015);
  static const Color bgSurface   = Color(0xFF1A1A21);
  static const Color bgOverlay   = Color(0xC0050507); // rgba(5,5,7,0.75)

  // Borders — мөнгөлөг chrome ирмэг
  static const Color hairline    = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
  static const Color hairline2   = Color(0x33FFFFFF); // rgba(255,255,255,0.20)

  // Text — хүйтэн цагаан/мөнгө
  static const Color textPrimary   = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFFB6BAC6);
  static const Color textTertiary  = Color(0xFF7A7E8C);
  static const Color textMono      = Color(0xFFC2C6D2);

  // ─── Chrome / silver (брэнд тэмдэг — disco owl) ───
  static const Color silver      = Color(0xFFD8DCE6);
  static const Color silverLight = Color(0xFFFFFFFF);
  static const Color silverDark  = Color(0xFF8A8E9C);
  static const Color steel       = Color(0xFF5A5E6C);

  // Accent — brushed chrome / silver (disco owl брэнд).
  // Цагаан текст уншигдахуйц гүн ган + мөнгөлөг гялбаа.
  static const Color accentStart  = Color(0xFF7E84A0); // steel-silver (signature)
  static const Color accentMid    = Color(0xFF626780); // graphite steel
  static const Color accentEnd    = Color(0xFFA8AEC4); // light silver edge
  static const Color accentPurple = Color(0xFF6E73D0); // cool steel-violet

  // Status
  static const Color success = Color(0xFF3DD68C);
  static const Color error   = Color(0xFFFF5470);
  static const Color warning = Color(0xFFFFB347);

  // ─── Light theme ───
  static const Color bgBaseLight      = Color(0xFFFAF6EE);
  static const Color bgElevatedLight  = Color(0xFFFFFFFF);
  static const Color bgSurfaceLight   = Color(0xFFF3ECDF);

  static const Color hairlineLight    = Color(0x141A0B2E);
  static const Color hairline2Light   = Color(0x291A0B2E);

  static const Color textPrimaryLight   = Color(0xFF1A0B2E);
  static const Color textSecondaryLight = Color(0xFF5C4A82);
  static const Color textTertiaryLight  = Color(0xFF9A8DB8);

  // ─── Accent gradient helper ───
  // Brushed chrome — гэрэлтэх мөнгөн ирмэг → ган төв (цагаан текст уншигдана)
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9DA3BC), Color(0xFF5E6379), Color(0xFF868CA6)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient accentGradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x55A8AEC4), Color(0x33808698)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7B2FF7), Color(0xFFB14CF7), accentStart],
  );

  // ─── Chrome / mirror gradient (disco owl брэнд) ───
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

  // Aurora background
  static const RadialGradient auroraGradient = RadialGradient(
    center: Alignment(-0.6, -0.6),
    radius: 1.2,
    colors: [Color(0x40FF4D8D), Colors.transparent],
  );
}
