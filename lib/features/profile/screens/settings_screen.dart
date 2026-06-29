import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../widgets/invite_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifLikes = true;
  bool _notifFollowers = true;
  bool _notifEvents = false;
  bool _privateAccount = false;
  bool _activityStatus = true;

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Данс устгах уу?', style: AppTextStyles.h3),
        content: Text(
          'Таны бүх пост, сэтгэгдэл, дагалт, мессеж бүрмөсөн устана. '
          'Энэ үйлдлийг буцаах боломжгүй.',
          style: AppTextStyles.bodySm.copyWith(
            color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary))),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: Text('Бүрмөсөн устгах', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    try {
      // 1) Эхлээд edge function-аар auth хэрэглэгчийг бүрмөсөн устгахыг оролдоно
      //    (deploy хийгдсэн бол бүх дата + auth устана)
      try {
        await Supabase.instance.client.functions.invoke('delete-account');
      } catch (_) {
        // 2) Function deploy хийгдээгүй бол — profiles устгах (контент cascade)
        await Supabase.instance.client.from('profiles').delete().eq('id', me);
      }
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go(AppRoutes.authLanding);
    } catch (e) {
      if (mounted) _toast('Устгахад алдаа: $e');
    }
  }

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
          _Row(icon: Icons.language_outlined, label: 'Language',
            onTap: () => context.push(AppRoutes.langSelect)),
          _Row(icon: Icons.palette_outlined, label: 'Appearance',
            onTap: () => _toast('Тун удахгүй — одоогоор Dark горим')),

          _Section('NOTIFICATIONS'),
          _Row(icon: Icons.favorite_border, label: 'Likes & Comments',
            trailing: _toggle(_notifLikes, (v) => setState(() => _notifLikes = v))),
          _Row(icon: Icons.person_add_outlined, label: 'New Followers',
            trailing: _toggle(_notifFollowers, (v) => setState(() => _notifFollowers = v))),
          _Row(icon: Icons.event_outlined, label: 'Events & Invites',
            trailing: _toggle(_notifEvents, (v) => setState(() => _notifEvents = v))),

          _Section('PRIVACY'),
          _Row(icon: Icons.lock_person_outlined, label: 'Private Account',
            trailing: _toggle(_privateAccount, (v) => setState(() => _privateAccount = v))),
          _Row(icon: Icons.visibility_outlined, label: 'Activity Status',
            trailing: _toggle(_activityStatus, (v) => setState(() => _activityStatus = v))),

          _Section('PAYMENTS'),
          _Row(icon: Icons.receipt_long_outlined, label: 'QPay History',
            onTap: () => _toast('Төлбөрийн түүх хоосон байна')),
          _Row(icon: Icons.business_center_outlined, label: 'Business Dashboard',
            onTap: () => context.push(AppRoutes.business)),

          _Section('OTHER'),
          _Row(icon: Icons.person_add_alt_1_outlined, label: 'Найзаа урих',
            onTap: () => showInviteSheet(context)),
          _Row(icon: Icons.help_outline, label: 'Help',
            onTap: () => _toast('Тусламж: support@nightowl.ub')),
          _Row(
            icon: Icons.logout,
            label: 'Sign Out',
            color: AppColors.error,
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) context.go(AppRoutes.authLanding);
            },
          ),
          _Row(
            icon: Icons.delete_forever_outlined,
            label: 'Данс устгах',
            color: AppColors.error,
            onTap: _deleteAccount,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _toggle(bool val, ValueChanged<bool> onChanged) => Switch(
    value: val,
    onChanged: onChanged,
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
