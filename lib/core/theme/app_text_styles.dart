import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Өнгөнүүд нь AppColors.dyn* getter-ээр theme-aware —
/// Light горимд бараан, Dark горимд цайвар текст автоматаар буцаана.
abstract class AppTextStyles {
  // ─── Display (Inter — монгол кириллд тод, геометрик heading) ───
  static TextStyle get displayLg => GoogleFonts.inter(
    fontSize: 36, fontWeight: FontWeight.w800,
    letterSpacing: -0.72, color: AppColors.dynTextPrimary,
  );

  static TextStyle get displayMd => GoogleFonts.inter(
    fontSize: 28, fontWeight: FontWeight.w800,
    letterSpacing: -0.56, color: AppColors.dynTextPrimary,
  );

  static TextStyle get displaySm => GoogleFonts.inter(
    fontSize: 22, fontWeight: FontWeight.w800,
    letterSpacing: -0.44, color: AppColors.dynTextPrimary,
  );

  // ─── Heading (Inter) ───
  static TextStyle get h1 => GoogleFonts.inter(
    fontSize: 20, fontWeight: FontWeight.w700,
    letterSpacing: -0.2, color: AppColors.dynTextPrimary,
  );

  static TextStyle get h2 => GoogleFonts.inter(
    fontSize: 17, fontWeight: FontWeight.w700,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get h3 => GoogleFonts.inter(
    fontSize: 15, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary,
  );

  // ─── Body ───
  static TextStyle get bodyLg => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w400,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get bodyMd => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get bodySm => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.dynTextSecondary,
  );

  static TextStyle get bodyXs => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.dynTextSecondary,
  );

  // ─── Label ───
  static TextStyle get labelLg => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get labelMd => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary, letterSpacing: 0.2,
  );

  // 11px — Material/HIG-ийн уншигдах доод хязгаар.
  static TextStyle get labelSm => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w600,
    color: AppColors.dynTextSecondary,
    letterSpacing: 0.8, height: 1.2,
  );

  // ─── Хэсгийн гарчиг — жижиг uppercase шошго (letterSpacing 1.2) ───
  // Хэрэглээ: Text('ГАРЧИГ', style: AppTextStyles.sectionLabel)
  static TextStyle get sectionLabel => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w700,
    letterSpacing: 1.2, color: AppColors.dynTextTertiary,
  );

  // ─── Mono ───
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.dynTextMono, letterSpacing: 0.5,
  );

  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
    fontSize: 10, fontWeight: FontWeight.w400,
    color: AppColors.dynTextTertiary, letterSpacing: 1.4,
  );

  // ─── Button ───
  static TextStyle get btn => GoogleFonts.inter(
    fontSize: 15, fontWeight: FontWeight.w700,
    letterSpacing: 0.2, color: AppColors.dynTextPrimary,
  );

  static TextStyle get btnSm => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary,
  );
}
