import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/mesh_gradient.dart';
import '../../../core/widgets/app_motion.dart';
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
  final _scroll = ScrollController();
  bool _entranceStarted = false;
  // Default 'mn' — UB-first апп тул англи flash гарахгүй
  String _locale = 'mn';

  int get _slideNumber => widget.slide.clamp(1, 3);

  @override
  void initState() {
    super.initState();
    // Сонгосон хэлийг уншина (lang_select дээр хадгалсан)
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _locale = p.getString('locale') ?? 'mn');
    });
    // 12px орчим гулсалт + fade — богино, premium мэдрэмжтэй easeOut
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _showEntrance();
  }

  void _showEntrance({bool restart = false}) {
    if (AppMotion.reduced(context) || !TickerMode.of(context)) {
      _ctrl.stop();
      _ctrl.value = 1;
      _entranceStarted = true;
    } else if (!_entranceStarted || restart) {
      _entranceStarted = true;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(OnboardingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide != widget.slide) {
      _showEntrance(restart: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_slideNumber < 3) {
      context.go('${AppRoutes.onboarding}?slide=${_slideNumber + 1}');
    } else {
      // Onboarding дууссан — flag тэмдэглэнэ, эс бөгөөс дараагийн
      // орох болгонд слайдууд дахин харагдана
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarded', true);
      if (!mounted) return;
      // Native дээр permission дэлгэц OS prompt дууддаггүй (web-only) — алгасна
      context.go(kIsWeb ? AppRoutes.permLocation : AppRoutes.authLanding);
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
          title:
              _locale == 'en' ? 'Find your place tonight' : 'Оройн газраа ол',
          sub: _locale == 'en'
              ? 'Explore Ulaanbaatar bars, clubs and live music venues on the map. Save the places you want to visit.'
              : 'Улаанбаатарын бар, клуб, амьд хөгжмийн газруудыг газрын зураг дээрээс харж, дуртайгаа хадгалаарай.',
          color: AppColors.accentStart),
      // Shared moments — existing photo, story and messaging features.
      _SlideData(
          illustration: 'assets/images/illustrations/onb_live.svg',
          title: _locale == 'en' ? 'Share your moments' : 'Мөчөө хамт хуваалц',
          sub: _locale == 'en'
              ? 'Post photos, videos and stories. Follow your friends and stay in touch through messages.'
              : 'Зураг, бичлэг, story нийтэлж, найзуудаа даган, мессежээр холбоотой байгаарай.',
          color: AppColors.neonCyan),
      // map / discover → neon map illustration (pink/magenta glow)
      _SlideData(
          illustration: 'assets/images/illustrations/onb_map.svg',
          title: _locale == 'en'
              ? 'Your location, your choice'
              : 'Байршлаа өөрөө сонго',
          sub: _locale == 'en'
              ? 'Allow location to find nearby places, or explore the map without it. Night Owl is free to use.'
              : 'Ойрхон газраа хайхдаа байршлын зөвшөөрөл өгч болно. Зөвшөөрөлгүйгээр ч газрын зургийг үзэж, аппыг үнэгүй ашиглана.',
          color: AppColors.accentEnd),
    ];
    final data = slides[_slideNumber - 1];
    // Гэрэлтэлтэд үргэлж тод неон өнгө — цайвар горимд бараан cyan бохир
    // уур болохоос сэргийлнэ (харанхуй горимд өөрчлөлтгүй)
    final glow = AppColors.toDark(data.color)!;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // Удаан хөдөлдөг mesh gradient дэвсгэр
          const Positioned.fill(child: MeshGradientBackground()),
          // Слайд бүрд зөөлөн шилждэг неон aura (гүн + өнгөт уур амьсгал)
          _OnboardAura(accent: glow),
          SafeArea(
            child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                    controller: _scroll,
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ── Дээд бар — progress pill (зүүн) + Алгасах (баруун) ──
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 10, 8, 0),
                                  child: Row(
                                    children: [
                                      _ProgressPill(slide: _slideNumber),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: _skip,
                                        child: Text(s.btnSkip,
                                            style: AppTextStyles.labelMd
                                                .copyWith(
                                                    color: AppColors
                                                        .textSecondary)),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Медальон — томруулсан, дэлгэцийн голд ──
                                SizedBox(
                                  height: (constraints.maxHeight * 0.38)
                                      .clamp(180.0, 300.0),
                                  child: FadeTransition(
                                    opacity: _fade,
                                    child: SlideTransition(
                                      position: _slide,
                                      child: Center(
                                        child: _GlassIconMedallion(
                                            illustration: data.illustration,
                                            glow: glow,
                                            size: 210),
                                      ),
                                    ),
                                  ),
                                ),

                                // ── Текст блок — доод талд, CTA-ийн яг дээр зүүн зэрэгцээ ──
                                FadeTransition(
                                  opacity: _fade,
                                  child: SlideTransition(
                                    position: _slide,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Слайдын дугаар — mono eyebrow
                                          // (цайвар горимд уншигдахуйц бараан бэх — accent-ийг textPrimary руу холино)
                                          Text('0$_slideNumber — 03',
                                              style: AppTextStyles.monoSm.copyWith(
                                                  letterSpacing: 2,
                                                  color: AppColors.isDarkMode
                                                      ? data.color.withValues(
                                                          alpha: 0.85)
                                                      : Color.lerp(
                                                          data.color,
                                                          AppColors
                                                              .textPrimaryLight,
                                                          0.35))),
                                          const SizedBox(height: 10),
                                          Text(data.title,
                                              style: AppTextStyles.displayMd
                                                  .copyWith(height: 1.12)),
                                          const SizedBox(height: 12),
                                          Text(data.sub,
                                              style: AppTextStyles.bodyMd
                                                  .copyWith(
                                                      color: AppColors
                                                          .textSecondary,
                                                      height: 1.55)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),

                                // ── CTA — pill primary, дэлгэцийн доод захад ──
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: GradientButton(
                                    label: _slideNumber == 3
                                        ? s.btnStart
                                        : s.btnContinue,
                                    onPressed: _next,
                                    borderRadius: 999,
                                    trailing: Icon(
                                        _slideNumber == 3
                                            ? Icons.auto_awesome_rounded
                                            : Icons.arrow_forward_rounded,
                                        color: Colors.white,
                                        size: 19),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ))))),
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
  const _SlideData(
      {required this.illustration,
      required this.title,
      required this.sub,
      required this.color});
}

// ───────────────────────── onboarding UI bits ─────────────────────────

/// Dots → progress pill — шилэн pill дотор 3 сегмент + "1/3" тоолуур.
class _ProgressPill extends StatelessWidget {
  final int slide;
  const _ProgressPill({required this.slide});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(3, (i) {
              final active = i + 1 == slide;
              final done = i + 1 < slide;
              return AnimatedContainer(
                duration: AppMotion.duration(
                    context, const Duration(milliseconds: 220)),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(right: 5),
                width: active ? 22 : 8,
                height: 5,
                decoration: BoxDecoration(
                  // Идэвхтэй сегмент — cyan chrome gradient + гэрэлтэлт
                  gradient: active ? AppColors.chromeGradient : null,
                  color: active
                      ? null
                      : (done
                          ? AppColors.neonCyan.withValues(alpha: 0.55)
                          : AppColors.hairline2),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: active
                      ? [
                          BoxShadow(
                              color: AppColors.neonCyan.withValues(alpha: 0.55),
                              blurRadius: 12,
                              spreadRadius: -1)
                        ]
                      : null,
                ),
              );
            }),
            const SizedBox(width: 4),
            Text('$slide/3',
                style: AppTextStyles.monoSm.copyWith(
                    letterSpacing: 1, color: AppColors.textSecondary)),
          ],
        ),
      );
}

/// Слайдын өнгөнд тааруулсан зөөлөн неон aura — login дэлгэцийн blob маягаар.
class _OnboardAura extends StatelessWidget {
  final Color accent;
  const _OnboardAura({required this.accent});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration:
                AppMotion.duration(context, const Duration(milliseconds: 600)),
            child: Stack(
              key: ValueKey(accent.toARGB32()),
              children: [
                Positioned(
                  top: -120,
                  right: -100,
                  child: _blob(280, accent.withValues(alpha: 0.30)),
                ),
                Positioned(
                  top: 60,
                  left: -120,
                  child: _blob(
                      260, AppColors.neonCyanDark.withValues(alpha: 0.12)),
                ),
                Positioned(
                  bottom: -130,
                  left: 10,
                  child: _blob(
                      300, AppColors.accentPurple.withValues(alpha: 0.16)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
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
    required this.illustration,
    required this.glow,
    this.size = 168,
  }) : pulse = true;
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
        vsync: this, duration: const Duration(milliseconds: 2600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.pulse && !AppMotion.reduced(context) && TickerMode.of(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0.5;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sz = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = widget.pulse ? _c.value : 0.5; // 0..1
        return SizedBox(
          width: sz,
          height: sz,
          child: Stack(alignment: Alignment.center, children: [
            // Гадна неон гэрэлтэлт (амьсгалдаг)
            Container(
                width: sz * 0.86,
                height: sz * 0.86,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(
                      color: widget.glow.withValues(alpha: 0.35 + 0.25 * t),
                      blurRadius: 50 + 30 * t,
                      spreadRadius: 6 + 8 * t),
                ])),
            // Шилэн медальон — blur-гүй gradient glass (web perf).
            // Цайвар горимд неон SVG уншигдахуйц байхаар шөнийн бараан шил.
            Container(
              width: sz * 0.82,
              height: sz * 0.82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColors.isDarkMode
                        ? [
                            Colors.white.withValues(alpha: 0.16),
                            widget.glow.withValues(alpha: 0.10),
                            Colors.white.withValues(alpha: 0.04),
                          ]
                        : [
                            AppColors.bgSurfaceDark.withValues(alpha: 0.90),
                            Color.alphaBlend(
                              widget.glow.withValues(alpha: 0.18),
                              AppColors.bgElevatedDark,
                            ).withValues(alpha: 0.92),
                            AppColors.bgBaseDark.withValues(alpha: 0.94),
                          ]),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22), width: 1.4),
              ),
            ),
            // Дотор зөөлөн өнгөт гэрэл
            Container(
                width: sz * 0.5,
                height: sz * 0.5,
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
              top: sz * 0.16,
              left: sz * 0.26,
              child: Container(
                  width: sz * 0.22,
                  height: sz * 0.10,
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
