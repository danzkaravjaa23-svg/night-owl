import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/mesh_gradient.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';

class OnboardingScreen extends StatefulWidget {
  final int slide;
  const OnboardingScreen({super.key, required this.slide});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  String _locale = 'en';

  @override
  void initState() {
    super.initState();
    // Сонгосон хэлийг уншина (lang_select дээр хадгалсан)
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _locale = p.getString('locale') ?? 'en');
    });
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _next() async {
    if (widget.slide < 3) {
      context.go('${AppRoutes.onboarding}?slide=${widget.slide + 1}');
    } else {
      context.go(AppRoutes.permLocation);
    }
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (!mounted) return;
    context.go(AppRoutes.authLanding);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(_locale);
    final slides = [
      // nightlife / bar → neon cocktail illustration (magenta glow)
      _SlideData(
        illustration: 'assets/images/illustrations/onb_nightlife.svg',
        title: s.onb1Title, sub: s.onb1Sub, color: AppColors.accentStart),
      // live / broadcast → neon turntable illustration (cyan glow)
      _SlideData(
        illustration: 'assets/images/illustrations/onb_live.svg',
        title: s.onb2Title, sub: s.onb2Sub, color: AppColors.neonCyan),
      // map / discover → neon map illustration (pink/magenta glow)
      _SlideData(
        illustration: 'assets/images/illustrations/onb_map.svg',
        title: s.onb3Title, sub: s.onb3Sub, color: AppColors.accentEnd),
    ];
    final data = slides[widget.slide - 1];

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // Удаан хөдөлдөг mesh gradient дэвсгэр
          const Positioned.fill(child: MeshGradientBackground()),
          // Слайд бүрд зөөлөн шилждэг неон aura (гүн + өнгөт уур амьсгал)
          _OnboardAura(accent: data.color),
          SafeArea(
            child: Column(
              children: [
                // Skip button
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: _skip,
                    child: Text(s.btnSkip,
                      style: AppTextStyles.labelMd.copyWith(color: AppColors.textSecondary)),
                  ),
                ),
                const Spacer(),
                FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GlassIconMedallion(
                            illustration: data.illustration,
                            glow: data.color, size: 168),
                          const SizedBox(height: 32),
                          Text(data.title,
                            style: AppTextStyles.displayMd,
                            textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Text(data.sub,
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary, height: 1.5),
                            textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final active = i + 1 == widget.slide;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        // Идэвхтэй цэг — неон cyan gradient + зөөлөн гэрэлтэлт
                        gradient: active ? AppColors.chromeGradient : null,
                        color: active ? null : AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: AppColors.neonCyan.withValues(alpha: 0.55),
                                  blurRadius: 12, spreadRadius: -1),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: GradientButton(
                    label: widget.slide == 3 ? s.btnStart : s.btnContinue,
                    onPressed: _next,
                    trailing: Icon(
                      widget.slide == 3
                          ? Icons.auto_awesome_rounded
                          : Icons.arrow_forward_rounded,
                      color: Colors.white, size: 19),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideData {
  final String illustration;
  final String title, sub;
  final Color color;
  const _SlideData({required this.illustration, required this.title, required this.sub, required this.color});
}

// ───────────────────────── onboarding UI bits ─────────────────────────

/// Слайдын өнгөнд тааруулсан зөөлөн неон aura — login дэлгэцийн blob маягаар.
class _OnboardAura extends StatelessWidget {
  final Color accent;
  const _OnboardAura({required this.accent});

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: Stack(
          key: ValueKey(accent.value),
          children: [
            Positioned(
              top: -120, right: -100,
              child: _blob(280, accent.withValues(alpha: 0.30)),
            ),
            Positioned(
              top: 60, left: -120,
              child: _blob(260, AppColors.neonCyan.withValues(alpha: 0.12)),
            ),
            Positioned(
              bottom: -130, left: 10,
              child: _blob(300, AppColors.accentPurple.withValues(alpha: 0.16)),
            ),
          ],
        ),
      ),
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

/// Frosted шилэн том медальон + Material icon + амьсгалдаг неон гэрэлтэлт.
/// Emoji-г орлуулсан premium вариант — өнгөт icon, glow boxShadow.
class _GlassIconMedallion extends StatefulWidget {
  final String illustration;
  final Color glow;
  final double size;
  final bool pulse;
  const _GlassIconMedallion({
    required this.illustration, required this.glow,
    this.size = 168, this.pulse = true,
  });
  @override
  State<_GlassIconMedallion> createState() => _GlassIconMedallionState();
}

class _GlassIconMedallionState extends State<_GlassIconMedallion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sz = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = widget.pulse ? _c.value : 0.5; // 0..1
        return SizedBox(
          width: sz, height: sz,
          child: Stack(alignment: Alignment.center, children: [
            // Гадна неон гэрэлтэлт (амьсгалдаг)
            Container(
              width: sz * 0.86, height: sz * 0.86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: widget.glow.withValues(alpha: 0.35 + 0.25 * t),
                    blurRadius: 50 + 30 * t, spreadRadius: 6 + 8 * t),
                ])),
            // Frosted шилэн медальон
            ClipRRect(
              borderRadius: BorderRadius.circular(sz),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: sz * 0.82, height: sz * 0.82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.16),
                        widget.glow.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.04),
                      ]),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22), width: 1.4),
                  ),
                ),
              ),
            ),
            // Дотор зөөлөн өнгөт гэрэл
            Container(
              width: sz * 0.5, height: sz * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  widget.glow.withValues(alpha: 0.5),
                  Colors.transparent,
                ]))),
            // Neon illustration (SVG) — өөрийн неон өнгөтэй, glow-г медальон өгнө
            SvgPicture.asset(widget.illustration,
              width: sz * 0.56, height: sz * 0.56),
            // Дээд талын specular highlight (шилэн гялбаа)
            Positioned(
              top: sz * 0.16, left: sz * 0.26,
              child: Container(
                width: sz * 0.22, height: sz * 0.10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(sz),
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0.0),
                  ]))),
            ),
          ]),
        );
      },
    );
  }
}
