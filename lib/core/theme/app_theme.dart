import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get dark => _buildTheme(isDark: true);
  static ThemeData get light => _buildTheme(isDark: false);

  static ThemeData _buildTheme({required bool isDark}) {
    final bg       = isDark ? AppColors.bgBase      : AppColors.bgBaseLight;
    final elevated = isDark ? AppColors.bgElevated  : AppColors.bgElevatedLight;
    final surface  = isDark ? AppColors.bgSurface   : AppColors.bgSurfaceLight;
    final textPri  = isDark ? AppColors.textPrimary : AppColors.textPrimaryLight;
    final textSec  = isDark ? AppColors.textSecondary : AppColors.textSecondaryLight;
    final hairline = isDark ? AppColors.hairline    : AppColors.hairlineLight;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary:   AppColors.accentStart,
        onPrimary: Colors.white,
        secondary: AppColors.accentPurple,
        onSecondary: Colors.white,
        error:     AppColors.error,
        onError:   Colors.white,
        surface:   surface,
        onSurface: textPri,
      ),
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).copyWith(
        bodyLarge:  TextStyle(color: textPri, fontSize: 16),
        bodyMedium: TextStyle(color: textPri, fontSize: 14),
        bodySmall:  TextStyle(color: textSec, fontSize: 12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPri,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w700, color: textPri,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: elevated,
        selectedItemColor: AppColors.neonCyan,
        unselectedItemColor: textSec,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        // Premium glass card — slightly tighter radius, deeper separation
        color: isDark ? elevated.withValues(alpha: 0.72) : elevated,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: hairline, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Шилэн талбар — dark горимд бага зэрэг тунгалаг
        fillColor: isDark ? surface.withValues(alpha: 0.72) : surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.neonCyan, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: AppColors.error.withValues(alpha: 0.6)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
        hintStyle: TextStyle(color: textSec.withValues(alpha: 0.8), fontSize: 14),
        labelStyle: TextStyle(color: textSec, fontSize: 14),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
        prefixIconColor: textSec,
        suffixIconColor: textSec,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textTertiary.withValues(alpha: 0.35);
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
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
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
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: textPri, size: 24),
      snackBarTheme: SnackBarThemeData(
        // Glass dark — хөвөгч, hairline хүрээтэй, радиус 14
        backgroundColor: isDark ? const Color(0xF0121218) : elevated,
        contentTextStyle: GoogleFonts.inter(
            color: isDark ? AppColors.textPrimary : textPri,
            fontSize: 14, fontWeight: FontWeight.w500),
        actionTextColor: AppColors.neonCyan,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: isDark ? AppColors.hairline : hairline),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
