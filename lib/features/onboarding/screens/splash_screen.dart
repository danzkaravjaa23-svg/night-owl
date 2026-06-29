import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/router/app_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;   // нэг удаагийн орох анимаци
  late AnimationController _pulse;  // давтагдах гялбаа/ачаалал
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.easeOutBack)));
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2400), _navigate);
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final hasOnboarded = prefs.getBool('onboarded') ?? false;
    final locale = prefs.getString('locale');
    if (!mounted) return;
    if (locale == null) {
      context.go(AppRoutes.langSelect);
    } else if (!hasOnboarded) {
      context.go('${AppRoutes.onboarding}?slide=1');
    } else {
      context.go(AppRoutes.authLanding);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // disco owl — цэвэр хар дэвсгэр
      body: Stack(
        children: [
          // Мөнгөлөг гялтгануур оч
          const Positioned.fill(child: _Sparkles()),
          // Төв контент
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _OwlLogo(pulse: _pulse),
                    const SizedBox(height: 28),
                    NightOwlLogoText(fontSize: 38),
                    const SizedBox(height: 8),
                    Text('UB · ШӨНИЙН НИЙГЭМ',
                      style: AppTextStyles.mono.copyWith(
                        fontSize: 10, letterSpacing: 2.5,
                        color: const Color(0xFFB8B8C0))),
                  ],
                ),
              ),
            ),
          ),
          // Доод: ачааллаж байна
          Positioned(
            bottom: 64, left: 0, right: 0,
            child: FadeTransition(
              opacity: _fade,
              child: Column(children: [
                _LoadingText(pulse: _pulse),
                const SizedBox(height: 18),
                const Text('© 2025 Night Owl UB',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11,
                    color: Color(0xFF6E6E78), letterSpacing: 0.5)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Disco owl logo — asset зураг (байхгүй бол fallback) + мөнгөлөг гэрэлтэлт
class _OwlLogo extends StatelessWidget {
  final Animation<double> pulse;
  const _OwlLogo({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, child) {
        final t = (math.sin(pulse.value * 2 * math.pi) + 1) / 2; // 0..1
        return SizedBox(
          width: 230, height: 230,
          child: Stack(alignment: Alignment.center, children: [
            // Мөнгөлөг амьсгалдаг гэрэлтэлт
            Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.10 + 0.10 * t),
                    blurRadius: 50 + 24 * t, spreadRadius: 6 + 6 * t),
                  BoxShadow(color: AppColors.accentStart.withValues(alpha: 0.10 + 0.08 * t),
                    blurRadius: 60, spreadRadius: 2),
                ])),
            child!,
          ]),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.asset(
          'assets/images/owl_logo.png',
          width: 210, height: 210, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      ),
    );
  }

  // Зураг хараахан хадгалаагүй үед — мөнгөлөг шилэн owl медальон
  Widget _fallback() => Container(
    width: 180, height: 180,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [
        Color(0xFFE8E8F0), Color(0xFF9A9AA8), Color(0xFF3A3A44),
      ], stops: [0.0, 0.55, 1.0]),
    ),
    child: const Center(child: Text('🦉', style: TextStyle(fontSize: 92))),
  );
}

/// "Ачааллаж байна" + хөдөлдөг цэгүүд
class _LoadingText extends StatelessWidget {
  final Animation<double> pulse;
  const _LoadingText({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final dots = ((pulse.value * 3).floor() % 3) + 1; // 1..3
        final shimmer = (math.sin(pulse.value * 2 * math.pi) + 1) / 2;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                Color.lerp(const Color(0xFF8A8A95), Colors.white, shimmer)))),
            const SizedBox(width: 10),
            Text('Ачааллаж байна${'.' * dots}',
              style: TextStyle(
                fontSize: 13, letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
                color: Color.lerp(
                  const Color(0xFF9A9AA8), Colors.white, shimmer * 0.7))),
          ]);
      },
    );
  }
}

/// Цагаан/мөнгөлөг гялтгануур оч (disco sparkle)
class _Sparkles extends StatelessWidget {
  const _Sparkles();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SparklePainter());
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white;
    for (var i = 0; i < 70; i++) {
      final x = (i * 137.5) % size.width;
      final y = (i * 97.3) % size.height;
      final r = (i % 5 == 0) ? 1.4 : 0.7;
      p.color = Colors.white.withValues(alpha: i % 5 == 0 ? 0.5 : 0.22);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
