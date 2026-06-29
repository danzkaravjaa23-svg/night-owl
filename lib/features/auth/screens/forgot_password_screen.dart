import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  Future<void> _send() async {
    if (_emailCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailCtrl.text.trim(),
      );
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new,
                  color: AppColors.textSecondary, size: 20),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _sent ? _SentView() : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    const Text('🔐', style: TextStyle(fontSize: 52)),
                    const SizedBox(height: 24),
                    Text('Reset Password', style: AppTextStyles.displayMd),
                    const SizedBox(height: 8),
                    Text('Enter your email and we\'ll send you a reset link.',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary, height: 1.5)),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: 'your@email.com'),
                    ),
                    const SizedBox(height: 32),
                    GradientButton(
                      label: _loading ? 'Sending...' : 'Send Reset Link',
                      onPressed: _loading ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SentView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.success.withValues(alpha: 0.15),
          ),
          child: const Icon(Icons.mark_email_read_outlined,
            color: AppColors.success, size: 40),
        ),
        const SizedBox(height: 24),
        Text('Check your email', style: AppTextStyles.h1),
        const SizedBox(height: 12),
        Text('We sent a password reset link. Check your inbox.',
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.textSecondary, height: 1.5),
          textAlign: TextAlign.center),
        const SizedBox(height: 40),
        GradientButton(
          label: 'Back to Sign In',
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
