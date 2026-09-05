import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';

/// Нууц үг сэргээх холбоосоор ирсэн хэрэглэгчид шинэ нууц үг тавих дэлгэц.
/// Splash нь AuthChangeEvent.passwordRecovery event-ийг барьж энэ дэлгэцийг нээнэ.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pwCtrl      = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey     = GlobalKey<FormState>();
  bool _showPw   = false;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Recovery session байхгүй бол (холбоос хугацаа дууссан) — landing руу
    if (Supabase.instance.client.auth.currentSession == null) {
      setState(() => _error =
          'Холбоосын хугацаа дууссан байна. Нууц үг сэргээхийг дахин хүсээрэй.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _pwCtrl.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Нууц үг амжилттай шинэчлэгдлээ')));
      // Splash-с pageless route-оор нээгдсэн бол эхлээд хаана,
      // дараа нь feed рүү шилжинэ
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
      context.go(AppRoutes.feed);
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() => _error = m.contains('should be different')
          ? 'Шинэ нууц үг хуучин нууц үгээс өөр байх ёстой.'
          : 'Нууц үг шинэчилж чадсангүй. Дахин оролдоно уу.');
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Алдаа гарлаа. Сүлжээгээ шалгана уу.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          const AuthAura(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 32, 26, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AuthGlyph(icon: Icons.password_rounded),
                    const SizedBox(height: 22),
                    Text('Шинэ нууц үг',
                      style: AppTextStyles.displayMd.copyWith(height: 1.15)),
                    const SizedBox(height: 10),
                    Text('Дансандаа шинэ нууц үг тохируулна уу.',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary, height: 1.5)),
                    const SizedBox(height: 34),

                    const FieldLabel('Шинэ нууц үг'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _pwCtrl,
                      obscureText: !_showPw,
                      autofillHints: const [AutofillHints.newPassword],
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: authInputDec(
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        suffix: IconButton(
                          onPressed: () => setState(() => _showPw = !_showPw),
                          icon: Icon(
                            _showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textTertiary, size: 20,
                          ),
                        ),
                      ),
                      validator: (v) => v!.length >= kPasswordMinLength
                          ? null : 'Хамгийн багадаа $kPasswordMinLength тэмдэгт',
                    ),
                    const SizedBox(height: 18),

                    const FieldLabel('Нууц үг давтах'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: !_showPw,
                      autofillHints: const [AutofillHints.newPassword],
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: authInputDec(
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded),
                      validator: (v) => v == _pwCtrl.text
                          ? null : 'Нууц үг таарахгүй байна',
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      AuthErrorBox(_error!),
                    ],

                    const SizedBox(height: 32),
                    GradientButton(
                      label: _loading ? 'Хадгалж байна...' : 'Нууц үг шинэчлэх',
                      onPressed: _loading ? null : _save,
                      borderRadius: 16,
                      trailing: _loading
                          ? const BtnSpinner()
                          : const Icon(Icons.check_rounded,
                              color: Colors.white, size: 19),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
