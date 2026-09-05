import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/widgets/mesh_gradient.dart';
import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';
import '../../../core/services/supabase_service.dart';

class AuthLandingScreen extends StatefulWidget {
  const AuthLandingScreen({super.key});

  @override
  State<AuthLandingScreen> createState() => _AuthLandingScreenState();
}

class _AuthLandingScreenState extends State<AuthLandingScreen> {
  bool _gLoading = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // Удаан хөдөлдөг mesh gradient дэвсгэр
          const Positioned.fill(child: MeshGradientBackground()),
          // Хоёр туйлт atmospheric glow — magenta зүүн дээд, cyan баруун доод
          const _LandingAura(),
          // Starfield
          Positioned.fill(child: CustomPaint(painter: _StarPainter())),
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
                          // Owl mark — disco owl брэнд тэмдэг + шалан дээрх тусгал
                          const AuthEntrance(child: _HeroOwl()),
                          const SizedBox(height: 4),
                          // Title — display хэмжээтэй hero гарчиг
                          AuthEntrance(
                            index: 1,
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: TextSpan(
                                style: AppTextStyles.displayLg,
                                children: [
                                  WidgetSpan(
                                    child: GradientText(
                                      'Шөнө',
                                      style: AppTextStyles.displayLg.copyWith(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                  const TextSpan(text: ' эхэлж байна'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AuthEntrance(
                            index: 2,
                            child: Text(
                              "UB-гийн шөнийн амьдрал · нэг tap-аар",
                              style: AppTextStyles.bodyMd.copyWith(
                                color: AppColors.textSecondary,
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
                        child: GradientButton(
                          label: 'Нэвтрэх',
                          borderRadius: 999,
                          onPressed: () => context.push(AppRoutes.login),
                        ),
                      ),
                      const SizedBox(height: 14),
                      AuthEntrance(
                        index: 4,
                        child: _OutlineBtn(
                          label: 'Бүртгэл үүсгэх',
                          onTap: () => context.push(AppRoutes.register),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const AuthEntrance(index: 5, child: OrDivider()),
                      const SizedBox(height: 18),
                      // Google — жинхэнэ OAuth
                      AuthEntrance(
                        index: 6,
                        child: _OutlineBtn(
                          label: _gLoading
                              ? 'Түр хүлээнэ үү...'
                              : 'Google-ээр үргэлжлүүлэх',
                          leading: _gLoading
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.textSecondary))
                              : const GoogleMark(),
                          onTap: _gLoading ? null : _googleSignIn,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Footer micro text
                      AuthEntrance(
                        index: 7,
                        child: Text('UB · ШӨНИЙН НИЙГЭМ · 2025',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.monoSm.copyWith(
                            letterSpacing: 2, color: AppColors.textTertiary)),
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

/// Том owl hero + доод талын тусгал — хөмөрсөн лого gradient маскаар бүдгэрнэ.
class _HeroOwl extends StatelessWidget {
  const _HeroOwl();

  static const double _size = 180;
  static const double _reflectH = 56;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const OwlLogoMark(size: _size),
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
          color: AppColors.bgElevated.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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
          child: _blob(360, AppColors.neonCyan.withValues(alpha: 0.10))),
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

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.35);
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
