import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
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

  @override
  void initState() {
    super.initState();
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
    final locale = 'en'; // will come from provider
    final s = AppStrings.of(locale);
    final slides = [
      _SlideData(emoji: '🌃', title: s.onb1Title, sub: s.onb1Sub, color: AppColors.accentStart),
      _SlideData(emoji: '📡', title: s.onb2Title, sub: s.onb2Sub, color: AppColors.accentPurple),
      _SlideData(emoji: '🗺️', title: s.onb3Title, sub: s.onb3Sub, color: AppColors.accentEnd),
    ];
    final data = slides[widget.slide - 1];

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // Aurora
          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [data.color.withOpacity(0.3), Colors.transparent],
                ),
              ),
            ),
          ),
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
                          Text(data.emoji, style: const TextStyle(fontSize: 80)),
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
                      width: active ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? AppColors.accentStart : AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(3),
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
  final String emoji, title, sub;
  final Color color;
  const _SlideData({required this.emoji, required this.title, required this.sub, required this.color});
}
