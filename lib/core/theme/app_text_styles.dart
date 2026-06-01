import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

abstract class AppTextStyles {
  // ─── Display (Manrope bold — heading) ───
  static TextStyle get displayLg => GoogleFonts.manrope(
    fontSize: 36, fontWeight: FontWeight.w800,
    letterSpacing: -0.72, color: AppColors.textPrimary,
  );

  static TextStyle get displayMd => GoogleFonts.manrope(
    fontSize: 28, fontWeight: FontWeight.w800,
    letterSpacing: -0.56, color: AppColors.textPrimary,
  );

  static TextStyle get displaySm => GoogleFonts.manrope(
    fontSize: 22, fontWeight: FontWeight.w800,
    letterSpacing: -0.44, color: AppColors.textPrimary,
  );

  // ─── Heading ───
  static TextStyle get h1 => GoogleFonts.manrope(
    fontSize: 20, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle get h2 => GoogleFonts.manrope(
    fontSize: 17, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle get h3 => GoogleFonts.manrope(
    fontSize: 15, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ─── Body ───
  static TextStyle get bodyLg => GoogleFonts.manrope(
    fontSize: 16, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyMd => GoogleFonts.manrope(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodySm => GoogleFonts.manrope(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static TextStyle get bodyXs => GoogleFonts.manrope(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // ─── Label ───
  static TextStyle get labelLg => GoogleFonts.manrope(
    fontSize: 14, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get labelMd => GoogleFonts.manrope(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary, letterSpacing: 0.2,
  );

  static TextStyle get labelSm => GoogleFonts.manrope(
    fontSize: 10, fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.8, height: 1.2,
  );

  // ─── Mono ───
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.textMono, letterSpacing: 0.5,
  );

  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
    fontSize: 9, fontWeight: FontWeight.w400,
    color: AppColors.textTertiary, letterSpacing: 1.4,
  );

  // ─── Button ───
  static TextStyle get btn => GoogleFonts.manrope(
    fontSize: 15, fontWeight: FontWeight.w700,
    letterSpacing: 0.2, color: AppColors.textPrimary,
  );

  static TextStyle get btnSm => GoogleFonts.manrope(
    fontSize: 13, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
}
