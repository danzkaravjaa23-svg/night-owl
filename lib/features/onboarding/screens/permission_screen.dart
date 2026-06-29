import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/router/app_router.dart';

enum PermissionKind { location, notification }

class PermissionScreen extends StatelessWidget {
  final PermissionKind kind;
  const PermissionScreen({super.key, required this.kind});

  void _allow(BuildContext context) {
    if (kind == PermissionKind.location) {
      context.go(AppRoutes.permNotif);
    } else {
      context.go(AppRoutes.authLanding);
    }
  }

  void _skip(BuildContext context) {
    if (kind == PermissionKind.location) {
      context.go(AppRoutes.permNotif);
    } else {
      context.go(AppRoutes.authLanding);
    }
  }

  @override
  Widget build(BuildContext context) {
    const s = AppStrings.en;
    final isLoc = kind == PermissionKind.location;
    final emoji  = isLoc ? '📍' : '🔔';
    final title  = isLoc ? s.permLocTitle   : s.permNotifTitle;
    final body   = isLoc ? s.permLocBody    : s.permNotifBody;
    final color  = isLoc ? AppColors.accentEnd : AppColors.accentPurple;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 52))),
              ),
              const SizedBox(height: 32),
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
                onPressed: () => _allow(context),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _skip(context),
                child: Text(s.btnLater,
                  style: AppTextStyles.labelMd.copyWith(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
