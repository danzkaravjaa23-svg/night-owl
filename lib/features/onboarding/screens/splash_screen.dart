import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/router/app_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fade  = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7, curve: Curves.easeOutBack)),
    );

    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2200), _navigate);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // Aurora background
          Positioned.fill(
            child: CustomPaint(painter: _SplashAuroraPainter()),
          ),
          // Starfield dots
          const _Starfield(),
          // Center content
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Owl logo
                    _OwlLogo(),
                    const SizedBox(height: 24),
                    // App name
                    NightOwlLogoText(fontSize: 36),
                    const SizedBox(height: 8),
                    Text(
                      'UB · ШӨНИЙН НИЙГЭМ',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        letterSpacing: 2.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom tagline
          Positioned(
            bottom: 48,
            left: 0, right: 0,
            child: FadeTransition(
              opacity: _fade,
              child: const Text(
                '© 2025 Night Owl UB',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OwlLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.accentStart.withOpacity(0.5),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Center(
        child: Text('🦉', style: TextStyle(fontSize: 48)),
      ),
    );
  }
}

class _Starfield extends StatelessWidget {
  const _Starfield();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _StarfieldPainter()),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.4);
    final rng = List.generate(60, (i) => i);
    for (final i in rng) {
      final x = (i * 137.5 % size.width);
      final y = (i * 97.3 % size.height);
      final r = (i % 3 == 0) ? 1.2 : 0.7;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _SplashAuroraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void drawGlow(Offset center, Color color, double radius) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withOpacity(0.35), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
    drawGlow(Offset(size.width * 0.2, size.height * 0.3), AppColors.accentStart,  size.width * 0.5);
    drawGlow(Offset(size.width * 0.8, size.height * 0.25), AppColors.accentEnd,   size.width * 0.5);
    drawGlow(Offset(size.width * 0.5, size.height * 0.7), AppColors.accentPurple, size.width * 0.6);
  }

  @override
  bool shouldRepaint(_) => false;
}
