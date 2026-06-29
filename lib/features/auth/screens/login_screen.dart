import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _pwCtrl    = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _showPw     = false;
  bool _loading    = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      // Хуучин session-ийг бүрэн цэвэрлэж байж шинээр нэвтрэх
      // (өөр хаягаар солих үед хуучин нь үлдэхээс сэргийлнэ)
      if (Supabase.instance.client.auth.currentUser != null) {
        await Supabase.instance.client.auth.signOut();
      }
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );
      if (!mounted) return;
      if (res.session == null) {
        setState(() => _error = 'Нэвтрэх боломжгүй. И-мэйл баталгаажаагүй байж магадгүй.');
        return;
      }
      context.go(AppRoutes.feed);
    } on AuthException catch (e) {
      // Supabase-ийн тодорхой алдааг ойлгомжтой болгох
      final m = e.message.toLowerCase();
      setState(() {
        if (m.contains('invalid login') || m.contains('credentials')) {
          _error = 'И-мэйл эсвэл нууц үг буруу байна.';
        } else if (m.contains('email not confirmed') || m.contains('confirm')) {
          _error = 'И-мэйл хаягаа баталгаажуулаагүй байна.';
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      setState(() => _error = 'Нэвтрэхэд алдаа гарлаа. Сүлжээгээ шалгана уу.');
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
          // Aurora top right
          Positioned(
            top: -120, right: -100,
            child: Container(
              width: 320, height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accentPurple.withValues(alpha: 0.35), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Back
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                      color: AppColors.textSecondary, size: 20),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('The night\nmissed you 🌙',
                            style: AppTextStyles.displayMd.copyWith(height: 1.2)),
                          const SizedBox(height: 8),
                          Text('Дахин нэвтрээд party-даа эргэн нэгдээрэй',
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary)),
                          const SizedBox(height: 40),

                          // Email
                          _InputLabel(label: 'Email'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: const InputDecoration(hintText: 'your@email.com'),
                            validator: (v) => v!.contains('@') ? null : 'Valid email required',
                          ),
                          const SizedBox(height: 20),

                          // Password
                          _InputLabel(label: 'Password'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _pwCtrl,
                            obscureText: !_showPw,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _showPw = !_showPw),
                                icon: Icon(
                                  _showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: AppColors.textSecondary, size: 20,
                                ),
                              ),
                            ),
                            validator: (v) => v!.length >= 6 ? null : 'Min 6 characters',
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                    color: AppColors.error, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_error!,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppColors.error))),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push(AppRoutes.forgotPassword),
                              child: Text('Forgot password?',
                                style: AppTextStyles.labelSm.copyWith(
                                  color: AppColors.accentStart)),
                            ),
                          ),
                          const SizedBox(height: 32),

                          GradientButton(
                            label: _loading ? 'Signing in...' : 'Sign In',
                            onPressed: _loading ? null : _signIn,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Don't have an account? ",
                                style: AppTextStyles.bodyMd.copyWith(
                                  color: AppColors.textSecondary)),
                              GestureDetector(
                                onTap: () => context.push(AppRoutes.register),
                                child: Text('Register',
                                  style: AppTextStyles.labelLg.copyWith(
                                    color: AppColors.accentStart)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  final String label;
  const _InputLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(label,
    style: AppTextStyles.labelMd.copyWith(color: AppColors.textSecondary,
      letterSpacing: 0.8));
}
