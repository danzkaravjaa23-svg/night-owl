import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/mesh_gradient.dart';
import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';
import '../../../core/services/supabase_service.dart';

/// Нүүр хуудас — "шөнө эхэлж байна" шөнийн тэнгэрийн 10 секундын давталт:
/// анивчих одод + 4 хошуут гялбаа, сүүлт од, шар шувуу мөсөн цэнхэр → ягаан
/// гэрлээр "цэнэглэгдэнэ", гарчиг неоноор амьсгална, товчнуудаар гялгар туяа
/// гүйнэ. Шөнийн тэнгэр тул горимоос үл хамааран ХАРАНХУЙ (splash шиг).
class AuthLandingScreen extends StatefulWidget {
  const AuthLandingScreen({super.key});

  @override
  State<AuthLandingScreen> createState() => _AuthLandingScreenState();
}

class _AuthLandingScreenState extends State<AuthLandingScreen>
    with SingleTickerProviderStateMixin {
  bool _gLoading = false;

  // Бүх анимацийн нэг цаг — 0..1 = 10 секунд, тасралтгүй давтагдана
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  @override
  void initState() {
    super.initState();
    // Google-ээс буцахад session солих алдаа гарсан бол нуухгүй харуулна
    final err = lastAuthCallbackError;
    if (err != null) {
      lastAuthCallbackError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Google нэвтрэлт: $err'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 12),
        ));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Хөдөлгөөн багасгах" асаалттай бол тайван, хөдлөхгүй тэнгэр
    if (MediaQuery.of(context).disableAnimations) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  // Google OAuth — жинхэнэ нэвтрэлт (web дээр бүтэн хуудас redirect)
  Future<void> _googleSignIn() async {
    setState(() => _gLoading = true);
    try {
      await signInWithGoogle();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Google-ээр нэвтрэхэд алдаа гарлаа. Дахин оролдоно уу.')));
      }
    } finally {
      if (mounted) setState(() => _gLoading = false);
    }
  }

  // Товчны гялгар туяа — товч бүр өөрийн цагийн цонхонд
  Widget _shine(double a, double b, Widget child, {double glowFrom = -1}) =>
      AnimatedBuilder(
        animation: _loop,
        child: child,
        builder: (_, c) => _Shine(
          progress: _window(_loop.value, a, b),
          borderGlow: glowFrom < 0 ? 0 : _bump(_loop.value, glowFrom, glowFrom + 0.06, glowFrom + 0.14),
          child: c!,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.bgBaseDark,
        body: Stack(
          children: [
            // Удаан хөдөлдөг mesh gradient дэвсгэр
            const Positioned.fill(child: MeshGradientBackground(forceDark: true)),
            // Хоёр туйлт atmospheric glow — magenta зүүн дээд, cyan баруун доод
            const _LandingAura(),
            // Шөнийн тэнгэр — од, гялбаа, сүүлт од
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _NightSkyPainter(_loop)),
                ),
              ),
            ),
            // Content
            SafeArea(
              child: Column(
                children: [
                  // ── Дээд hero — том owl + тусгал + display гарчиг ──
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Owl mark — цэнхэр/ягаан гэрлээр цэнэглэгдэнэ
                            AuthEntrance(child: _HeroOwl(loop: _loop)),
                            const SizedBox(height: 4),
                            // Title — неон туяа амьсгална
                            AuthEntrance(index: 1, child: _GlowTitle(loop: _loop)),
                            const SizedBox(height: 12),
                            AuthEntrance(
                              index: 2,
                              child: Text(
                                "UB-гийн шөнийн амьдрал · нэг tap-аар",
                                style: AppTextStyles.bodyMd.copyWith(
                                  color: AppColors.textSecondaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── CTA блок — дэлгэцийн доод захад бэхлэгдсэн ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthEntrance(
                          index: 3,
                          child: _shine(0.36, 0.46, GradientButton(
                            label: 'Нэвтрэх',
                            borderRadius: 999,
                            onPressed: () => context.push(AppRoutes.login),
                          )),
                        ),
                        const SizedBox(height: 14),
                        AuthEntrance(
                          index: 4,
                          child: _shine(0.64, 0.74, _OutlineBtn(
                            label: 'Бүртгэл үүсгэх',
                            onTap: () => context.push(AppRoutes.register),
                          ), glowFrom: 0.66),
                        ),
                        const SizedBox(height: 18),
                        const AuthEntrance(index: 5, child: OrDivider(onDark: true)),
                        const SizedBox(height: 18),
                        // Google — жинхэнэ OAuth
                        AuthEntrance(
                          index: 6,
                          child: _shine(0.68, 0.78, _OutlineBtn(
                            label: _gLoading
                                ? 'Түр хүлээнэ үү...'
                                : 'Google-ээр үргэлжлүүлэх',
                            leading: _gLoading
                                ? const SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.textSecondaryDark))
                                : const GoogleMark(),
                            onTap: _gLoading ? null : _googleSignIn,
                          ), glowFrom: 0.68),
                        ),
                        const SizedBox(height: 18),
                        // Footer micro text
                        AuthEntrance(
                          index: 7,
                          child: Text('UB · ШӨНИЙН НИЙГЭМ · 2025',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.monoSm.copyWith(
                              letterSpacing: 2, color: AppColors.textTertiaryDark)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── 10с давталтын цаг ───────────────────────────
//  0.14–0.31  гарчиг бүтнээрээ неон туяа
//  0.15–0.33  шар шувуу мөсөн цэнхэр
//  0.31–0.38  сүүлт од A (баруун дээрээс)
//  0.36–0.46  "Нэвтрэх" гялгар туяа
//  0.43–0.60  шар шувуу ягаан тэсрэлт + 4 хошуут гялбаа
//  0.46–0.60  "Шөнө" туяа
//  0.47–0.53  сүүлт од B (гарчгийн зүүн тийш)
//  0.64–0.80  хүрээтэй товчнуудын гялгар + ирмэгийн гэрэл
//  0.88–1.00  "Шөнө" зөөлөн туяа (1.0 дээр 0 → залгаасгүй давталт)

/// a→peak өсөөд peak→b буурна (зөөлөн), гадна нь 0.
double _bump(double t, double a, double peak, double b) {
  if (t <= a || t >= b) return 0;
  final x = t < peak ? (t - a) / (peak - a) : (b - t) / (b - peak);
  return x * x * (3 - 2 * x);
}

/// [a,b] цонх дотор 0..1, гадна нь -1 (идэвхгүй).
double _window(double t, double a, double b) =>
    (t <= a || t >= b) ? -1 : (t - a) / (b - a);

// ─────────────────────────────── Owl ───────────────────────────────

/// Том owl hero + доод талын тусгал — хөмөрсөн лого gradient маскаар бүдгэрнэ.
/// Үе үе мөсөн цэнхэр, дараа нь ягаан гэрлээр будагдаж гэрэлтэнэ.
class _HeroOwl extends StatelessWidget {
  final Animation<double> loop;
  const _HeroOwl({required this.loop});

  static const double _size = 180;
  static const double _reflectH = 56;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedBuilder(
        animation: loop,
        builder: (_, __) => _ChargedOwl(
          size: _size,
          cyan: _bump(loop.value, 0.15, 0.23, 0.33),
          pink: _bump(loop.value, 0.43, 0.50, 0.60),
        ),
      ),
      // Тусгал — scaleY:-1 хөмрөлт + доошоо бүдгэрэх gradient маск (0.15)
      SizedBox(
        width: _size, height: _reflectH,
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.transparent],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _reflectH / _size,
              child: Opacity(
                opacity: 0.15,
                child: Transform.scale(
                  scaleY: -1,
                  child: const OwlLogoMark(size: _size),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _ChargedOwl extends StatelessWidget {
  final double size;
  final double cyan; // 0..1
  final double pink; // 0..1
  const _ChargedOwl({required this.size, required this.cyan, required this.pink});

  static const _ice = Color(0xFF8DEBFF);
  static const _rose = Color(0xFFFF5FD2);

  Widget _owl(Color tint) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.16),
    child: ColorFiltered(
      colorFilter: ColorFilter.mode(tint, BlendMode.srcATop),
      child: Image.asset('assets/images/owl_logo.png',
        width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final amt = math.max(cyan, pink);
    final tint = Color.lerp(_ice, _rose, pink / (cyan + pink + 1e-6))!;
    return SizedBox(
      width: size, height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Bloom — өнгөөр будсан бүдэг хуулбар ард нь
          if (amt > 0.01)
            Opacity(
              opacity: (amt * 0.9).clamp(0.0, 1.0),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: _owl(tint),
              ),
            ),
          OwlLogoMark(size: size),
          // Шар шувууг өөрийг нь өнгөөр будна — талстын хээ ил хэвээр
          if (amt > 0.01)
            Opacity(
              opacity: (amt * 0.55).clamp(0.0, 1.0),
              child: _owl(tint),
            ),
          // Толгой дээрх 4 хошуут гялбаа (ягаан үед хамгийн тод)
          if (amt > 0.01)
            Positioned(
              top: size * 0.06,
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(size * 0.9, size * 0.5),
                  painter: _FlarePainter(
                    amount: math.max(pink, cyan * 0.45),
                    color: tint,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FlarePainter extends CustomPainter {
  final double amount;
  final Color color;
  _FlarePainter({required this.amount, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (amount <= 0.01) return;
    final c = Offset(size.width / 2, size.height * 0.28);
    final len = size.width * 0.5 * amount;
    final core = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * amount)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final halo = Paint()
      ..color = color.withValues(alpha: 0.55 * amount)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(c, 22 * amount, halo);
    _star(canvas, c, len, len * 0.06, core);
    _star(canvas, c, len * 0.45, len * 0.05, core, rotate: math.pi / 4);
    canvas.drawCircle(c, 3.5 * amount, Paint()..color = Colors.white.withValues(alpha: amount));
  }

  void _star(Canvas canvas, Offset c, double len, double w, Paint p, {double rotate = 0}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rotate);
    for (var i = 0; i < 2; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(-len, 0)
          ..lineTo(0, -w)
          ..lineTo(len, 0)
          ..lineTo(0, w)
          ..close(),
        p,
      );
      canvas.rotate(math.pi / 2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlarePainter old) => old.amount != amount || old.color != color;
}

// ─────────────────────────────── Title ───────────────────────────────

/// "Шөнө эхэлж байна" — неон "Шөнө" + хромон "эхэлж байна".
/// • "Шөнө": 4 өнгийн неон градиент, ард нь байнгын зөөлөн гэрэлтэлт,
///   үе үе дээгүүр нь гялгар туяа гүйнэ.
/// • "эхэлж байна": шар шувуутай адил мөнгөлөг хром металл градиент.
/// • Цагийн хуваарийн дагуу неон туяа бүтэн гарчиг / зөвхөн "Шөнө" дээр амьсгална.
class _GlowTitle extends StatelessWidget {
  final Animation<double> loop;
  const _GlowTitle({required this.loop});

  static const _neon = Color(0xFFFF4FD8);

  // "Шөнө" — нил → фуксиа → ягаан → цайвар ягаан (гялбаатай төгсгөл)
  static const _nightGradient = LinearGradient(
    begin: Alignment(-1, -0.4),
    end: Alignment(1, 0.4),
    colors: [Color(0xFF8B5CF6), Color(0xFFD946EF), Color(0xFFFF2D8E), Color(0xFFFF8FCB)],
    stops: [0.0, 0.38, 0.72, 1.0],
  );

  // "эхэлж байна" — хром: дээр цагаан, дунд нь хүйтэн мөнгө, доод ирмэг дээр тусгал
  static const _chromeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF2F0FA), Color(0xFFB9BDD0), Color(0xFFE8E4F4)],
    stops: [0.0, 0.46, 0.78, 1.0],
  );

  // Хоёр хэсгийг ижил зохиомжоор байрлуулна — туяаны хуулбар яг давхцана
  static Widget _line(TextStyle base, Widget night, Widget rest) => RichText(
    textAlign: TextAlign.center,
    text: TextSpan(style: base, children: [
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: night,
      ),
      // Налуу "ө"-ийн сүүл дараагийн үг рүү орохгүй — энгийн зайнаас өргөн
      const WidgetSpan(child: SizedBox(width: 14)),
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: rest,
      ),
    ]),
  );

  static Widget _masked(Gradient g, String text, TextStyle style) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: g.createShader,
    child: Text(text, style: style.copyWith(color: Colors.white)),
  );

  @override
  Widget build(BuildContext context) {
    // "эхэлж байна" — Unbounded: өргөн футурист гротеск (хромон)
    final base = GoogleFonts.unbounded(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.1,
      color: AppColors.textPrimaryDark,
    );
    // "Шөнө" — Lobster: неон хаягийн бичмэл. Монгол ө/ү-г бүрэн агуулдаг
    // (Pacifico зэрэг бусад бичмэл фонтод "ө" байхгүй тул өөр фонтоор холилддог).
    final italic = GoogleFonts.lobster(
      fontSize: 44,
      height: 1.1,
      color: AppColors.textPrimaryDark,
    );

    // Суурь — өнгөт текст
    final title = _line(
      base,
      _masked(_nightGradient, 'Шөнө', italic),
      _masked(_chromeGradient, 'эхэлж байна', base),
    );

    return AnimatedBuilder(
      animation: loop,
      child: title,
      builder: (_, child) {
        final t = loop.value;
        final full = _bump(t, 0.14, 0.23, 0.31);
        final word = math.max(
          _bump(t, 0.46, 0.52, 0.60) * 0.9,
          _bump(t, 0.88, 0.95, 1.0) * 0.7,
        );
        // "Шөнө" үргэлж зөөлөн гэрэлтэнэ; хуваарьт агшинд тодорно
        final nightGlow = (0.38 + 0.62 * math.max(full, word)).clamp(0.0, 1.0);
        final shine = _window(t, 0.78, 0.88);

        Widget glowCopy(double nightA, double restA) => _line(
          base,
          Text('Шөнө', style: italic.copyWith(color: _neon.withValues(alpha: nightA))),
          Text('эхэлж байна', style: base.copyWith(color: _neon.withValues(alpha: restA))),
        );

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Өргөн зөөлөн неон гэрэлтэлт
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: glowCopy(nightGlow * 0.85, full * 0.8),
            ),
            // Ойрын тод гэрэлтэлт — ирмэгийг "неон хоолой" шиг болгоно
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: glowCopy(nightGlow * 0.55, full * 0.6),
            ),
            child!,
            // Гялгар туяа — "Шөнө" дээгүүр налуу цагаан зурвас гүйнэ
            if (shine >= 0)
              IgnorePointer(
                child: _line(
                  base,
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (r) => LinearGradient(
                      begin: const Alignment(-1, -0.6),
                      end: const Alignment(1, 0.6),
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.9 * math.sin(math.pi * shine)),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: [
                        (shine * 1.4 - 0.35).clamp(0.0, 1.0),
                        (shine * 1.4 - 0.2).clamp(0.0, 1.0),
                        (shine * 1.4 - 0.05).clamp(0.0, 1.0),
                      ],
                    ).createShader(r),
                    child: Text('Шөнө', style: italic.copyWith(color: Colors.white)),
                  ),
                  // Баруун хэсэг — зохиомж хадгалах зорилготой, үл харагдана
                  Text('эхэлж байна', style: base.copyWith(color: Colors.transparent)),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────── Buttons ───────────────────────────────

/// Товч дээгүүр налуу гялгар туяа гүйлгэнэ; [borderGlow] — ирмэгийн гэрэл.
class _Shine extends StatelessWidget {
  final double progress; // 0..1, <0 бол идэвхгүй
  final double borderGlow; // 0..1
  final Widget child;
  const _Shine({required this.progress, required this.borderGlow, required this.child});

  @override
  Widget build(BuildContext context) {
    if (progress < 0 && borderGlow <= 0.01) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: borderGlow > 0.01
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.75 * borderGlow),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.18 * borderGlow),
                          blurRadius: 14,
                        ),
                      ],
                    )
                  : const BoxDecoration(),
              child: progress >= 0
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: CustomPaint(painter: _ShinePainter(progress)),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShinePainter extends CustomPainter {
  final double p;
  _ShinePainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final band = w * 0.14;
    final skew = h * 0.8;
    final x = lerpDouble(-band - skew, w, Curves.easeInOut.transform(p))!;
    final a = math.sin(math.pi * p); // орж гарахдаа зөөлөн
    final path = Path()
      ..moveTo(x + skew, 0)
      ..lineTo(x + skew + band, 0)
      ..lineTo(x + band, h)
      ..lineTo(x, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.55 * a),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(x, 0, band + skew, h)),
    );
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.p != p;
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;

  const _OutlineBtn({required this.label, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      // Хоёрдогч glass товч — pill хэлбэр, bgElevated шилэн давхарга + hairline
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgElevatedDark.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2Dark),
        ),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimaryDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Text(label,
                  style: AppTextStyles.btn.onDark.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Sky ───────────────────────────────

/// Хоёр туйлт glow талбар — маш бага alpha, void black дээр уур амьсгал өгнө
class _LandingAura extends StatelessWidget {
  const _LandingAura();
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: Stack(children: [
        Positioned(top: -150, left: -130,
          child: _blob(340, AppColors.accentStart.withValues(alpha: 0.14))),
        Positioned(bottom: -160, right: -120,
          child: _blob(360, AppColors.neonCyanDark.withValues(alpha: 0.10))),
      ]),
    ),
  );

  Widget _blob(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Colors.transparent]),
    ),
  );
}

class _Star {
  final double x, y, r, alpha, phase;
  final int freq; // 10с-д хэдэн удаа анивчих — бүхэл тоо тул давталт залгаасгүй
  final Color color;
  const _Star(this.x, this.y, this.r, this.alpha, this.phase, this.freq, this.color);
}

class _Sparkle {
  final double x, y, size, phase;
  final int freq;
  final Color color;
  const _Sparkle(this.x, this.y, this.size, this.phase, this.freq, this.color);
}

/// Анивчих одод + 4 хошуут гялбаа + сүүлт од.
class _NightSkyPainter extends CustomPainter {
  final Animation<double> t;
  _NightSkyPainter(this.t) : super(repaint: t);

  static final List<_Star> _stars = _makeStars();
  static final List<_Sparkle> _sparkles = _makeSparkles();

  // Тогтмол үр — дэлгэц бүрт ижил тэнгэр
  static List<_Star> _makeStars() {
    var s = 20250926;
    double rnd() {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      return s / 0x7fffffff;
    }
    const tints = [Colors.white, Colors.white, Colors.white,
      Color(0xFFE6D9FF), Color(0xFFCFF5FF)];
    // Видеотой адил нягт, тод тэнгэр — цөөн хэдэн том од тодорно
    return List.generate(140, (_) => _Star(
      rnd(), rnd(),
      0.5 + rnd() * rnd() * 1.8,
      0.35 + rnd() * 0.6,
      rnd() * math.pi * 2,
      1 + (rnd() * 3).floor(),
      tints[(rnd() * tints.length).floor() % tints.length],
    ));
  }

  static List<_Sparkle> _makeSparkles() => const [
    _Sparkle(0.08, 0.07, 5.5, 0.0, 1, Colors.white),
    _Sparkle(0.86, 0.14, 4.5, 1.9, 2, Color(0xFFFFF3C4)),
    _Sparkle(0.66, 0.23, 6.0, 3.4, 1, Color(0xFFFFF3C4)),
    _Sparkle(0.93, 0.36, 4.0, 0.8, 2, Colors.white),
    _Sparkle(0.13, 0.42, 4.0, 4.4, 1, Color(0xFFE6D9FF)),
    _Sparkle(0.80, 0.55, 3.5, 2.6, 2, Colors.white),
    _Sparkle(0.04, 0.63, 5.0, 5.1, 1, Colors.white),
    _Sparkle(0.95, 0.72, 4.5, 1.2, 1, Color(0xFFCFF5FF)),
    _Sparkle(0.30, 0.88, 3.5, 3.9, 2, Colors.white),
    _Sparkle(0.72, 0.93, 4.0, 0.3, 1, Color(0xFFFFF3C4)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    const tau = math.pi * 2;
    final w = size.width, h = size.height;

    // Анивчих одод
    final dot = Paint();
    for (final st in _stars) {
      final tw = 0.55 + 0.45 * math.sin(tau * v * st.freq + st.phase);
      dot.color = st.color.withValues(alpha: (st.alpha * tw).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(st.x * w, st.y * h), st.r, dot);
    }

    // 4 хошуут гялбаа
    for (final sp in _sparkles) {
      final k = math.pow(0.5 + 0.5 * math.sin(tau * v * sp.freq + sp.phase), 3).toDouble();
      if (k < 0.04) continue;
      _sparkle(canvas, Offset(sp.x * w, sp.y * h), sp.size * (0.6 + 0.6 * k), sp.color, k);
    }

    // Сүүлт од A — баруун дээрээс зүүн доош
    _shootingStar(canvas, _window(v, 0.31, 0.38),
        Offset(w * 0.98, h * 0.08), Offset(w * 0.52, h * 0.30));
    // Сүүлт од B — гарчгийн зүүн тийш
    _shootingStar(canvas, _window(v, 0.47, 0.53),
        Offset(w * 0.46, h * 0.40), Offset(w * 0.02, h * 0.50));
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color, double k) {
    final p = Paint()..color = color.withValues(alpha: 0.95 * k);
    final glow = Paint()
      ..color = color.withValues(alpha: 0.35 * k)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8);
    canvas.drawCircle(c, r * 0.6, glow);
    final wdt = r * 0.16;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r, c.dy)
        ..lineTo(c.dx, c.dy - wdt)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + wdt)
        ..close()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + wdt, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - wdt, c.dy)
        ..close(),
      p,
    );
  }

  void _shootingStar(Canvas canvas, double p, Offset from, Offset to) {
    if (p < 0) return;
    final e = Curves.easeOutCubic.transform(p);
    final head = Offset.lerp(from, to, e)!;
    final dir = (to - from) / (to - from).distance;
    final tail = head - dir * 70 * math.min(1.0, p * 3);
    final a = math.sin(math.pi * p);
    canvas.drawLine(
      tail, head,
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          const Color(0xFFD9E4FF).withValues(alpha: 0.9 * a),
        ]).createShader(Rect.fromPoints(tail, head)),
    );
    canvas.drawCircle(head, 2.2, Paint()
      ..color = Colors.white.withValues(alpha: a)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
  }

  @override
  bool shouldRepaint(_NightSkyPainter old) => false; // repaint via Animation
}
