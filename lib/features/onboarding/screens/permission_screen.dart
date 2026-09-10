import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../utils/web_permissions.dart';

enum PermissionKind { location, notification }

class PermissionScreen extends StatefulWidget {
  final PermissionKind kind;
  const PermissionScreen({super.key, required this.kind});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  // Сонгосон хэлээр (default 'mn') — SharedPreferences-с уншина.
  AppStrings _s = AppStrings.mn;
  bool _requesting = false; // browser prompt хүлээж байгаа эсэх

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('locale') ?? 'mn';
    if (!mounted) return;
    setState(() => _s = locale == 'mn' ? AppStrings.mn : AppStrings.en);
  }

  // Дараагийн дэлгэц рүү — сүүлийн алхам дээр onboarded тэмдэглэнэ
  // (splash дахин onboarding харуулахгүй байх хамгаалалт)
  Future<void> _goNext() async {
    if (widget.kind == PermissionKind.location) {
      context.go(AppRoutes.permNotif);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarded', true);
      if (!mounted) return;
      context.go(AppRoutes.authLanding);
    }
  }

  // Зөвшөөрөх — browser-ийн жинхэнэ permission prompt-ыг дуудна
  Future<void> _allow(BuildContext context) async {
    setState(() => _requesting = true);
    if (widget.kind == PermissionKind.location) {
      await WebPermissions.requestLocation();
    } else {
      await WebPermissions.requestNotification();
    }
    if (!mounted) return;
    setState(() => _requesting = false);
    await _goNext();
  }

  void _skip(BuildContext context) => _goNext();

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final isLoc = widget.kind == PermissionKind.location;
    final illustration = isLoc
        ? 'assets/images/illustrations/perm_location.svg'
        : 'assets/images/illustrations/perm_notify.svg';
    final title = isLoc ? s.permLocTitle : s.permNotifTitle;
    final body  = isLoc ? s.permLocBody  : s.permNotifBody;
    // Per-kind accent: location → pink/red, notification → amber/magenta.
    final color = isLoc ? AppColors.accentEnd : AppColors.amber;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // ── Futurist Nightscape aura ──
          _PermAura(accent: color),
          SafeArea(
            child: Padding(
              // Хажуугийн зай — onboarding слайдтай ижил 20px
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x5, 10, AppSpacing.x5, AppSpacing.x6),
              child: Column(
                children: [
                  const Spacer(),
                  _PermGlyph(illustration: illustration, glow: color),
                  const SizedBox(height: 34),
                  Text(title,
                    style: AppTextStyles.displaySm,
                    textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(body,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textSecondary, height: 1.6),
                    textAlign: TextAlign.center),
                  const Spacer(),
                  GradientButton(
                    label: s.btnAllow,
                    borderRadius: AppRadii.md,
                    onPressed: _requesting ? null : () => _allow(context),
                    trailing: _requesting
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded,
                            color: Colors.white, size: 19),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _requesting ? null : () => _skip(context),
                    child: Text(s.btnLater,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.textSecondary)),
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

// ───────────────────────── permission UI bits ─────────────────────────

/// Glassy circle with a colored neon glow holding a Material icon.
class _PermGlyph extends StatelessWidget {
  final String illustration;
  final Color glow;
  const _PermGlyph({required this.illustration, required this.glow});

  @override
  Widget build(BuildContext context) => Container(
    width: 112, height: 112,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: glow.withValues(alpha: 0.45),
          blurRadius: 48, spreadRadius: -6),
        BoxShadow(color: glow.withValues(alpha: 0.22),
          blurRadius: 90, spreadRadius: 4),
      ],
    ),
    child: ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x99151515),
            shape: BoxShape.circle,
            border: Border.all(color: glow.withValues(alpha: 0.30)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SvgPicture.asset(illustration),
          ),
        ),
      ),
    ),
  );
}

class _PermAura extends StatelessWidget {
  final Color accent;
  const _PermAura({required this.accent});

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: Stack(children: [
        Positioned(
          top: -120, right: -110,
          child: _blob(280, AppColors.accentPurple.withValues(alpha: 0.30)),
        ),
        Positioned(
          top: 60, left: -130,
          child: _blob(260, AppColors.neonCyan.withValues(alpha: 0.14)),
        ),
        Positioned(
          bottom: -130, left: 0,
          child: _blob(320, accent.withValues(alpha: 0.20)),
        ),
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
