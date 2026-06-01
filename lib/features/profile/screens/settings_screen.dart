import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Settings', style: AppTextStyles.h2),
      ),
      body: ListView(
        children: [
          _Section('ACCOUNT'),
          _Row(icon: Icons.person_outline, label: 'Edit Profile',
            onTap: () => context.push(AppRoutes.setup)),
          _Row(icon: Icons.lock_outline, label: 'Change Password',
            onTap: () => context.push(AppRoutes.changePassword)),
          _Row(icon: Icons.language_outlined, label: 'Language'),
          _Row(icon: Icons.palette_outlined, label: 'Appearance'),

          _Section('NOTIFICATIONS'),
          _Row(icon: Icons.favorite_border, label: 'Likes & Comments',
            trailing: _toggle(true)),
          _Row(icon: Icons.person_add_outlined, label: 'New Followers',
            trailing: _toggle(true)),
          _Row(icon: Icons.event_outlined, label: 'Events & Invites',
            trailing: _toggle(false)),

          _Section('PRIVACY'),
          _Row(icon: Icons.lock_person_outlined, label: 'Private Account',
            trailing: _toggle(false)),
          _Row(icon: Icons.visibility_outlined, label: 'Activity Status',
            trailing: _toggle(true)),

          _Section('PAYMENTS'),
          _Row(icon: Icons.receipt_long_outlined, label: 'QPay History'),
          _Row(icon: Icons.business_center_outlined, label: 'Business Dashboard',
            onTap: () => context.push(AppRoutes.business)),

          _Section('OTHER'),
          _Row(icon: Icons.help_outline, label: 'Help'),
          _Row(
            icon: Icons.logout,
            label: 'Sign Out',
            color: AppColors.error,
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go(AppRoutes.authLanding);
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _toggle(bool val) => Switch(
    value: val,
    onChanged: (_) {},
    activeColor: AppColors.accentStart,
  );
}

class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Text(label, style: AppTextStyles.labelSm),
  );
}

class _Row extends StatelessWidget {
  final IconData icon; final String label;
  final Widget? trailing; final VoidCallback? onTap;
  final Color? color;
  const _Row({required this.icon, required this.label,
    this.trailing, this.onTap, this.color});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color ?? AppColors.textSecondary, size: 22),
    title: Text(label, style: AppTextStyles.bodyMd.copyWith(
      color: color ?? AppColors.textPrimary)),
    trailing: trailing ?? (onTap != null
      ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
      : null),
    onTap: onTap,
  );
}
