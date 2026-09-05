import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';

class LangSelectScreen extends StatefulWidget {
  const LangSelectScreen({super.key});

  @override
  State<LangSelectScreen> createState() => _LangSelectScreenState();
}

class _LangSelectScreenState extends State<LangSelectScreen> {
  // UB-first апп тул Монгол хэл default сонгогдсон байна
  String _selected = 'mn';

  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', _selected);
    if (!mounted) return;
    context.go('${AppRoutes.onboarding}?slide=1');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // ── Futurist Nightscape aura ──
          const _LangAura(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(),
                  // Owl logo hero — neon cyan ring + glow
                  const _Entrance(child: _OwlHero()),
                  const SizedBox(height: 32),
                  _Entrance(
                    index: 1,
                    child: Column(children: [
                      Text(
                        'Choose Language',
                        style: AppTextStyles.displaySm,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'Хэлээ сонгоно уу',
                        style: AppTextStyles.bodyMd
                            .copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 40),
                  _Entrance(
                    index: 2,
                    child: _LangTile(
                      flag: '🇺🇸', lang: 'English', native: 'English',
                      isSelected: _selected == 'en',
                      onTap: () => setState(() => _selected = 'en'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Entrance(
                    index: 3,
                    child: _LangTile(
                      flag: '🇲🇳', lang: 'Mongolian', native: 'Монгол',
                      isSelected: _selected == 'mn',
                      onTap: () => setState(() => _selected = 'mn'),
                    ),
                  ),
                  const Spacer(),
                  _Entrance(
                    index: 4,
                    child: GradientButton(
                      label: _selected == 'mn' ? 'Үргэлжлүүлэх' : 'Continue',
                      onPressed: _continue,
                      borderRadius: 16,
                      trailing: const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 19),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── owl logo hero ─────────────────────────

class _OwlHero extends StatelessWidget {
  const _OwlHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.neonCyan.withValues(alpha: 0.34),
            blurRadius: 40,
            spreadRadius: -6,
          ),
          BoxShadow(
            color: AppColors.neonCyan.withValues(alpha: 0.16),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      // Outer neon cyan ring — blur-гүй glass дотортой (web perf)
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.chromeGradient,
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgElevated.withValues(alpha: 0.85),
            border: Border.all(
              color: AppColors.neonCyan.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Image.asset(
            'assets/images/owl_logo.png',
            width: 92,
            height: 92,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.nightlight_round,
              color: AppColors.neonCyan,
              size: 46,
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── entrance stagger ─────────────────────────

/// Орох анимаци — fade + 12px гулсалт, index бүрт 40ms шатлана
class _Entrance extends StatelessWidget {
  final int index;
  final Widget child;
  const _Entrance({this.index = 0, required this.child});
  @override
  Widget build(BuildContext context) {
    final delay = index * 40;
    final total = 220 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOut),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

// ───────────────────────── language tile ─────────────────────────

class _LangTile extends StatefulWidget {
  final String flag, lang, native;
  final bool isSelected;
  final VoidCallback onTap;

  const _LangTile({
    required this.flag,
    required this.lang,
    required this.native,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_LangTile> createState() => _LangTileState();
}

class _LangTileState extends State<_LangTile> {
  bool _down = false;

  String get flag => widget.flag;
  String get lang => widget.lang;
  String get native => widget.native;
  bool get isSelected => widget.isSelected;

  @override
  Widget build(BuildContext context) {
    // Web мэдрэмж — hover заагч + дарахад зөөлөн агших
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: _tile(),
        ),
      ),
    );
  }

  Widget _tile() {
    // Сонгогдсон үед gradient hairline хүрээ (padding = хүрээний зузаан),
    // blur-гүй glass дотор — web дээр BackdropFilter удаан
    return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSelected ? AppColors.chromeGradient : null,
          color: isSelected ? null : AppColors.hairline2,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.neonCyan.withValues(alpha: 0.28),
                    blurRadius: 24,
                    spreadRadius: -6,
                  ),
                ]
              : null,
        ),
        child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? Color.alphaBlend(
                        AppColors.neonCyan.withValues(alpha: 0.07),
                        AppColors.bgElevated)
                    : AppColors.bgElevated.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(flag, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          native,
                          style: AppTextStyles.h3.copyWith(
                            color: isSelected
                                ? AppColors.neonCyan
                                : AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          lang,
                          style: AppTextStyles.bodyXs,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.neonCyan,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.neonCyan.withValues(alpha: 0.55),
                            blurRadius: 14,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.check,
                          size: 15, color: AppColors.bgBase),
                    ),
                ],
              ),
            ),
    );
  }
}

// ───────────────────────── aura background ─────────────────────────

class _LangAura extends StatelessWidget {
  const _LangAura();

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: IgnorePointer(
          child: Stack(children: [
            Positioned(
              top: -120,
              left: -110,
              child: _blob(280, AppColors.neonCyan.withValues(alpha: 0.18)),
            ),
            Positioned(
              top: -90,
              right: -120,
              child: _blob(260, AppColors.accentPurple.withValues(alpha: 0.28)),
            ),
            Positioned(
              bottom: -120,
              right: 10,
              child: _blob(300, AppColors.accentStart.withValues(alpha: 0.16)),
            ),
          ]),
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
