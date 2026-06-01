import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/router/app_router.dart';

class AuthLandingScreen extends StatelessWidget {
  const AuthLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // Multi-color aurora
          Positioned.fill(child: CustomPaint(painter: _AuthAuroraPainter())),
          // Starfield
          Positioned.fill(child: CustomPaint(painter: _StarPainter())),
          // Content
          SafeArea(
            child: Column(
              children: [
                // Top half — logo
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Owl mark
                      _OwlMark(),
                      const SizedBox(height: 24),
                      // Title
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: AppTextStyles.displayLg,
                          children: [
                            const TextSpan(text: 'The '),
                            WidgetSpan(
                              child: GradientText(
                                'Night',
                                style: AppTextStyles.displayLg.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const TextSpan(text: ' Begins'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "UB's bar & lounge social",
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),

                // Bottom half — buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GradientButton(
                        label: 'Sign In',
                        onPressed: () => context.push(AppRoutes.login),
                      ),
                      const SizedBox(height: 12),
                      _OutlineBtn(
                        label: 'Create Account',
                        onTap: () => context.push(AppRoutes.register),
                      ),
                      const SizedBox(height: 20),
                      // Divider
                      Row(children: [
                        const Expanded(child: Divider(color: AppColors.hairline)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('OR', style: AppTextStyles.monoSm),
                        ),
                        const Expanded(child: Divider(color: AppColors.hairline)),
                      ]),
                      const SizedBox(height: 20),
                      // Google
                      _OutlineBtn(
                        label: 'Continue with Google',
                        leading: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Center(
                            child: Text('G',
                              style: TextStyle(
                                color: Color(0xFF4285F4),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              )),
                          ),
                        ),
                        onTap: () => context.push(AppRoutes.setup),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OwlMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100, height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.accentStart.withOpacity(0.5),
            blurRadius: 40, spreadRadius: 4,
          ),
        ],
      ),
      child: const Center(child: Text('🦉', style: TextStyle(fontSize: 48))),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget? leading;

  const _OutlineBtn({required this.label, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Text(label, style: AppTextStyles.btn.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthAuroraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void g(Offset c, Color col, double r) {
      canvas.drawCircle(c, r, Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40)
        ..color = col.withOpacity(0.35));
    }
    g(Offset(size.width * 0.2, size.height * 0.3), AppColors.accentStart,  size.width * 0.45);
    g(Offset(size.width * 0.8, size.height * 0.25), AppColors.accentEnd,   size.width * 0.45);
    g(Offset(size.width * 0.5, size.height * 0.7), AppColors.accentPurple, size.width * 0.5);
    g(Offset(size.width * 0.15, size.height * 0.8), AppColors.accentStart, size.width * 0.35);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.35);
    for (var i = 0; i < 50; i++) {
      canvas.drawCircle(
        Offset(i * 137.5 % size.width, i * 97.3 % size.height),
        i % 3 == 0 ? 1.1 : 0.6,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
