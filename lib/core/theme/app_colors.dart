import 'package:flutter/material.dart';

/// NightOwl UB — Design tokens
/// Дизайн токенүүд — styles.css-с шууд хөрвүүлсэн
abstract class AppColors {
  // ─── Dark theme (default) ───
  static const Color bgBase      = Color(0xFF0B0118);
  static const Color bgElevated  = Color(0xFF1A0B2E);
  static const Color bgSurface   = Color(0xFF241141);
  static const Color bgOverlay   = Color(0xB80B0118); // rgba(11,1,24,0.72)

  // Borders
  static const Color hairline    = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const Color hairline2   = Color(0x24FFFFFF); // rgba(255,255,255,0.14)

  // Text
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB9A9D4);
  static const Color textTertiary  = Color(0xFF6E5E8A);
  static const Color textMono      = Color(0xFFC8B9E0);

  // Accent gradient
  static const Color accentStart  = Color(0xFFFF4D8D); // hot pink
  static const Color accentMid    = Color(0xFFFF7B5C); // coral
  static const Color accentEnd    = Color(0xFFFFB347); // amber
  static const Color accentPurple = Color(0xFF7B2FF7);

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
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentStart, accentMid, accentEnd],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient accentGradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x55FF4D8D), Color(0x33FFB347)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7B2FF7), Color(0xFFB14CF7), accentStart],
  );

  // Aurora background
  static const RadialGradient auroraGradient = RadialGradient(
    center: Alignment(-0.6, -0.6),
    radius: 1.2,
    colors: [Color(0x40FF4D8D), Colors.transparent],
  );
}
