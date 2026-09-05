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
  String? _error; // талбарын доор харуулах Монгол алдаа

  @override
  void dispose() { _newCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  void _snack(String msg, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: err ? AppColors.error : null,
      behavior: SnackBarBehavior.floating));
  }

  Future<void> _update() async {
    final pass = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    // ── Клиент талын шалгалт (сервер рүү илгээхээс өмнө) ──
    if (pass.isEmpty) {
      setState(() => _error = 'Шинэ нууц үгээ оруулна уу');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Нууц үг дор хаяж 6 тэмдэгт байх ёстой');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Нууц үг таарахгүй байна');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: pass));
      if (mounted) {
        context.pop();
        _snack('Нууц үг шинэчлэгдлээ ✓');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Supabase-ийн англи алдааг ойлгомжтой Монгол текст рүү хөрвүүлнэ
  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('at least') || s.contains('6 characters')) {
      return 'Нууц үг дор хаяж 6 тэмдэгт байх ёстой';
    }
    if (s.contains('same') || s.contains('different from')) {
      return 'Шинэ нууц үг хуучнаас өөр байх ёстой';
    }
    if (s.contains('network') || s.contains('socket') || s.contains('timeout')) {
      return 'Сүлжээний алдаа. Дахин оролдоно уу';
    }
    return 'Нууц үг шинэчилж чадсангүй';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgBase,
    appBar: AppBar(
      backgroundColor: AppColors.bgBase,
      leading: IconButton(onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
      title: Text('Нууц үг солих', style: AppTextStyles.h2),
    ),
    body: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Шинэ нууц үг', style: AppTextStyles.labelMd.copyWith(
          color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(controller: _newCtrl, obscureText: true,
          onChanged: (_) { if (_error != null) setState(() => _error = null); },
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '••••••••')),
        const SizedBox(height: 20),
        Text('Нууц үг баталгаажуулах', style: AppTextStyles.labelMd.copyWith(
          color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(controller: _confirmCtrl, obscureText: true,
          onChanged: (_) { if (_error != null) setState(() => _error = null); },
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: '••••••••')),
        // ── Алдааны мессеж (талбарын доор) ──
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                    color: AppColors.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_error!,
                    style: AppTextStyles.bodyXs.copyWith(color: AppColors.error))),
                ]),
              ),
        ),
        const SizedBox(height: 40),
        GradientButton(
          label: _loading ? 'Шинэчилж байна...' : 'Нууц үг шинэчлэх',
          onPressed: _loading ? null : _update),
      ]),
    ),
  );
}
