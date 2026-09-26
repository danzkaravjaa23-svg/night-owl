import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Gradient shimmer text — matches .ns-grad-text CSS class
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient gradient;

  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = AppColors.accentGradient,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(text, style: baseStyle),
    );
  }
}

/// Night Owl лого бичиг — "Night" металл/бэх градиент + неон "Owl" гэрэлтэлттэй.
///
/// Харанхуй дээр: хромон мөнгөлөг "Night" (шар шувуутай уялдана) + нил →
/// фуксиа → ягаан "Owl", ард нь зөөлөн неон гэрэл.
/// Цайвар дээр: гүн нил бэхэн "Night" + бараандуулсан неон "Owl" (цайвар
/// дэвсгэр дээр уншигдахуйц), гэрэлтэлт сул.
class NightOwlLogoText extends StatelessWidget {
  final double fontSize;
  final bool isMn;
  /// Горимоос үл хамааран харанхуй дэвсгэрийн хувилбар (splash мэт).
  final bool onDark;
  /// Хуучин API — өгвөл "Night" хэсэг энэ цул өнгөтэй болно.
  final Color? color;

  const NightOwlLogoText({
    super.key,
    this.fontSize = 22,
    this.isMn = false,
    this.onDark = false,
    this.color,
  });

  static const _chrome = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF2F0FA), Color(0xFFB9BDD0), Color(0xFFE8E4F4)],
    stops: [0.0, 0.46, 0.78, 1.0],
  );
  static const _ink = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color(0xFF1A0B2E), Color(0xFF2A1245), Color(0xFF45216E)],
    stops: [0.0, 0.55, 1.0],
  );
  static const _neonDark = LinearGradient(
    begin: Alignment(-1, -0.4), end: Alignment(1, 0.4),
    colors: [Color(0xFF8B5CF6), Color(0xFFD946EF), Color(0xFFFF2D8E), Color(0xFFFF8FCB)],
    stops: [0.0, 0.38, 0.72, 1.0],
  );
  static const _neonLight = LinearGradient(
    begin: Alignment(-1, -0.4), end: Alignment(1, 0.4),
    colors: [Color(0xFF7C3AED), Color(0xFFC026D3), Color(0xFFE11D74), Color(0xFFF0529C)],
    stops: [0.0, 0.38, 0.72, 1.0],
  );
  static const _glow = Color(0xFFFF4FD8);

  @override
  Widget build(BuildContext context) {
    final dark = onDark || AppColors.isDarkMode;
    // GoogleFonts — фонтыг runtime дээр татаж бүртгэдэг тул pubspec-д
    // bundle хийлгүйгээр брэнд бичиг баталгаатай гарна.
    // "Night" — Unbounded: өргөн футурист гротеск (хромон)
    final base = GoogleFonts.unbounded(
      fontSize: fontSize * 0.86,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      color: Colors.white,
    );
    // "Owl" — Lobster: неон хаягийн бичмэл (кирилл + монгол ө/ү дэмжинэ)
    final italic = GoogleFonts.lobster(
      fontSize: fontSize * 1.18,
      color: Colors.white,
    );
    final first = isMn ? 'Шөнийн' : 'Night';
    final second = isMn ? ' шувуухай' : ' Owl';

    Widget masked(Gradient g, String text, TextStyle style) => ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: g.createShader,
      child: Text(text, style: style),
    );

    // Хоёр хэсгийг baseline дээр — туяаны хуулбар яг давхцана
    Widget line(Widget a, Widget b) => RichText(
      text: TextSpan(style: base, children: [
        WidgetSpan(alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic, child: a),
        WidgetSpan(alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic, child: b),
      ]),
    );

    final main = line(
      color != null
          ? Text(first, style: base.copyWith(color: color))
          : masked(dark ? _chrome : _ink, first, base),
      masked(dark ? _neonDark : _neonLight, second, italic),
    );

    // Зөвхөн "Owl"-ийн ард неон гэрэл; "Night" хэсэг нь зай хадгална
    final glowCopy = line(
      Text(first, style: base.copyWith(color: Colors.transparent)),
      Text(second, style: italic.copyWith(
          color: _glow.withValues(alpha: dark ? 0.75 : 0.28))),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: fontSize * 0.32, sigmaY: fontSize * 0.32),
          child: glowCopy,
        ),
        if (dark)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
                sigmaX: fontSize * 0.1, sigmaY: fontSize * 0.1),
            child: Opacity(opacity: 0.6, child: glowCopy),
          ),
        main,
      ],
    );
  }
}
