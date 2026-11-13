import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Өнгөнүүд нь AppColors.dyn* getter-ээр theme-aware —
/// Light горимд бараан, Dark горимд цайвар текст автоматаар буцаана.
///
/// Inter нь pubspec.yaml-д 400/500/600/700/800 жинтэй НЭГ family тул
/// `copyWith(fontWeight: ...)` хийсэн ч жин бүр өөрийн файлаар (жинхэнэ
/// тод) зурагдана — Regular файлаас хуурамч тод үүсгэхгүй (DS-04).
abstract class AppTextStyles {
  /// pubspec.yaml-ийн `fonts:` хэсэгт бүртгэсэн Inter family.
  static const String fontFamily = 'Inter';

  // ─── Display (Inter — монгол кириллд тод, геометрик heading) ───
  static TextStyle get displayLg => TextStyle(
    fontFamily: fontFamily,
    fontSize: 36, fontWeight: FontWeight.w800,
    letterSpacing: -0.72, color: AppColors.dynTextPrimary,
  );

  static TextStyle get displayMd => TextStyle(
    fontFamily: fontFamily,
    fontSize: 28, fontWeight: FontWeight.w800,
    letterSpacing: -0.56, color: AppColors.dynTextPrimary,
  );

  static TextStyle get displaySm => TextStyle(
    fontFamily: fontFamily,
    fontSize: 22, fontWeight: FontWeight.w800,
    letterSpacing: -0.44, color: AppColors.dynTextPrimary,
  );

  // ─── Хуудас ба хэсгийн гарчиг ───
  /// Дэлгэцийн толгойн гарчиг (AppHeader.title) — 24/w800.
  static TextStyle get pageTitle => TextStyle(
    fontFamily: fontFamily,
    fontSize: 24, fontWeight: FontWeight.w800,
    letterSpacing: -0.3, color: AppColors.dynTextPrimary,
  );

  /// Sheet, dialog, карт, жагсаалтын блокийн гарчиг — 17/w700 (AppBar ба AlertDialog-ийн гарчиг).
  static TextStyle get title => TextStyle(
    fontFamily: fontFamily,
    fontSize: 17, fontWeight: FontWeight.w700,
    color: AppColors.dynTextPrimary,
  );

  // ─── Heading (Inter) ───
  static TextStyle get h1 => TextStyle(
    fontFamily: fontFamily,
    fontSize: 24, fontWeight: FontWeight.w700,
    letterSpacing: -0.2, color: AppColors.dynTextPrimary,
  );

  static TextStyle get h2 => TextStyle(
    fontFamily: fontFamily,
    fontSize: 19, fontWeight: FontWeight.w700,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get h3 => TextStyle(
    fontFamily: fontFamily,
    fontSize: 15, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary,
  );

  // ─── Body ───
  static TextStyle get bodyLg => TextStyle(
    fontFamily: fontFamily,
    fontSize: 16, fontWeight: FontWeight.w400,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get bodyMd => TextStyle(
    fontFamily: fontFamily,
    fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get bodySm => TextStyle(
    fontFamily: fontFamily,
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.dynTextSecondary,
  );

  static TextStyle get bodyXs => TextStyle(
    fontFamily: fontFamily,
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.dynTextSecondary,
  );

  /// Туслах мэдээлэл (огноо, тоо, зургийн тайлбар) — 12/w500.
  static TextStyle get caption => TextStyle(
    fontFamily: fontFamily,
    fontSize: 12, fontWeight: FontWeight.w500,
    color: AppColors.dynTextSecondary,
  );

  // ─── Label ───
  static TextStyle get labelLg => TextStyle(
    fontFamily: fontFamily,
    fontSize: 14, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary,
  );

  static TextStyle get labelMd => TextStyle(
    fontFamily: fontFamily,
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary, letterSpacing: 0.2,
  );

  // 11px — Material/HIG-ийн уншигдах доод хязгаар.
  static TextStyle get labelSm => TextStyle(
    fontFamily: fontFamily,
    fontSize: 11, fontWeight: FontWeight.w600,
    color: AppColors.dynTextSecondary,
    letterSpacing: 0.8, height: 1.2,
  );

  // ─── Хэсгийн гарчиг — жижиг uppercase шошго (letterSpacing 1.2) ───
  // Хэрэглээ: Text('ГАРЧИГ', style: AppTextStyles.sectionLabel)
  static TextStyle get sectionLabel => TextStyle(
    fontFamily: fontFamily,
    fontSize: 11, fontWeight: FontWeight.w700,
    letterSpacing: 1.2, color: AppColors.dynTextTertiary,
  );

  // ─── Mono (google_fonts — апп дотор багцалсан, сүлжээгүй) ───
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
    fontSize: 11, fontWeight: FontWeight.w400,
    color: AppColors.dynTextMono, letterSpacing: 0.5,
  );

  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
    fontSize: 10, fontWeight: FontWeight.w400,
    color: AppColors.dynTextTertiary, letterSpacing: 1.4,
  );

  // ─── Button ───
  static TextStyle get btn => TextStyle(
    fontFamily: fontFamily,
    fontSize: 15, fontWeight: FontWeight.w700,
    letterSpacing: 0.2, color: AppColors.dynTextPrimary,
  );

  static TextStyle get btnSm => TextStyle(
    fontFamily: fontFamily,
    fontSize: 13, fontWeight: FontWeight.w600,
    color: AppColors.dynTextPrimary,
  );
}

/// Үргэлж харанхуй гадаргуу (reels, story, live, видео, splash) дээрх текст.
/// `AppTextStyles.bodyMd.onDark` — гэрэл горимд ч цайвар текст хэвээр үлдэнэ.
extension TextStyleOnDark on TextStyle {
  TextStyle get onDark => copyWith(color: AppColors.toDark(color));
}
