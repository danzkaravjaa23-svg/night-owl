import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _newCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  Future<void> _update() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newCtrl.text));
      if (mounted) { context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated!'))); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgBase,
    appBar: AppBar(
      backgroundColor: AppColors.bgBase,
      leading: IconButton(onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
      title: Text('Change Password', style: AppTextStyles.h2),
    ),
    body: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('New Password', style: AppTextStyles.labelMd.copyWith(
          color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(controller: _newCtrl, obscureText: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '••••••••')),
        const SizedBox(height: 20),
        Text('Confirm Password', style: AppTextStyles.labelMd.copyWith(
          color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(controller: _confirmCtrl, obscureText: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '••••••••')),
        const SizedBox(height: 40),
        GradientButton(
          label: _loading ? 'Updating...' : 'Update Password',
          onPressed: _loading ? null : _update),
      ]),
    ),
  );
}
