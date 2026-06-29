import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';

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

  void _allow(BuildContext context) {
    if (widget.kind == PermissionKind.location) {
      context.go(AppRoutes.permNotif);
    } else {
      context.go(AppRoutes.authLanding);
    }
  }

  void _skip(BuildContext context) {
    if (widget.kind == PermissionKind.location) {
      context.go(AppRoutes.permNotif);
    } else {
      context.go(AppRoutes.authLanding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final isLoc = widget.kind == PermissionKind.location;
    final icon  = isLoc ? Icons.location_on_rounded : Icons.notifications_rounded;
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
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const Spacer(),
                  _PermGlyph(icon: icon, glow: color),
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
                    borderRadius: 16,
                    onPressed: () => _allow(context),
                    trailing: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 19),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _skip(context),
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
  final IconData icon;
  final Color glow;
  const _PermGlyph({required this.icon, required this.glow});

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
          child: Icon(icon, color: glow, size: 46),
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
