import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
          // ── Futurist Nightscape aura ──
          const _AuthAura(),
          SafeArea(
            child: Column(
              children: [
                // Top bar — back + eyebrow
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(children: [
                    _GlassBack(onTap: () => context.pop()),
                    const Spacer(),
                    Text('NIGHT OWL', style: AppTextStyles.monoSm.copyWith(
                      letterSpacing: 3, color: AppColors.textTertiary)),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 32, 26, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _AuthGlyph(icon: Icons.nightlight_round),
                          const SizedBox(height: 22),
                          Text('The night missed you 🌙',
                            style: AppTextStyles.displayMd.copyWith(height: 1.15)),
                          const SizedBox(height: 10),
                          Text('Дахин нэвтрээд party-даа эргэн нэгдээрэй',
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary)),
                          const SizedBox(height: 34),

                          // Email
                          const _FieldLabel('И-мэйл'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _dec(
                              hint: 'name@email.com',
                              icon: Icons.mail_outline_rounded),
                            validator: (v) => v!.contains('@') ? null : 'Valid email required',
                          ),
                          const SizedBox(height: 18),

                          // Password
                          const _FieldLabel('Нууц үг'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _pwCtrl,
                            obscureText: !_showPw,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _dec(
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
                            validator: (v) => v!.length >= 6 ? null : 'Min 6 characters',
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            _ErrorBox(_error!),
                          ],

                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push(AppRoutes.forgotPassword),
                              child: Text('Нууц үг мартсан уу?',
                                style: AppTextStyles.labelSm.copyWith(
                                  color: AppColors.neonCyan, letterSpacing: 0)),
                            ),
                          ),
                          const SizedBox(height: 22),

                          GradientButton(
                            label: _loading ? 'Нэвтрэж байна...' : 'Sign In',
                            onPressed: _loading ? null : _signIn,
                            borderRadius: 16,
                            trailing: _loading
                                ? null
                                : const Icon(Icons.arrow_forward_rounded,
                                    color: Colors.white, size: 19),
                          ),
                          const SizedBox(height: 22),
                          const _OrDivider(),
                          const SizedBox(height: 22),
                          OutlineButton(
                            label: 'Continue with Google',
                            icon: const _GoogleMark(),
                            onPressed: () => context.push(AppRoutes.setup),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Footer — anchored to the bottom of the screen
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 8, 26, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Шинэ хэрэглэгч үү? ',
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: () => context.push(AppRoutes.register),
                        child: Text('Бүртгүүлэх',
                          style: AppTextStyles.labelLg.copyWith(
                            color: AppColors.neonCyan)),
                      ),
                    ],
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

// ───────────────────────── shared auth UI bits ─────────────────────────

InputDecoration _dec({required String hint, required IconData icon, Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 20),
      suffixIcon: suffix,
    );

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(label, style: AppTextStyles.labelMd.copyWith(
      color: AppColors.textSecondary, letterSpacing: 0.4)),
  );
}

class _GlassBack extends StatelessWidget {
  final VoidCallback onTap;
  const _GlassBack({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0x99151515),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline2),
          ),
          child: const Icon(Icons.chevron_left_rounded,
            color: AppColors.textPrimary, size: 24),
        ),
      ),
    ),
  );
}

class _AuthGlyph extends StatelessWidget {
  final IconData icon;
  const _AuthGlyph({required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    width: 56, height: 56,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.20),
          blurRadius: 22, spreadRadius: -4),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x99151515),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Icon(icon, color: AppColors.neonCyan, size: 26),
        ),
      ),
    ),
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(color: AppColors.hairline)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text('OR', style: AppTextStyles.monoSm.copyWith(letterSpacing: 2)),
    ),
    const Expanded(child: Divider(color: AppColors.hairline)),
  ]);
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  static const String _svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z"/><path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"/><path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"/><path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571.001-.001.002-.001.003-.002l6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z"/></svg>';

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _svg,
    width: 20,
    height: 20,
  );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: AppColors.error, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(message,
        style: AppTextStyles.bodySm.copyWith(color: AppColors.error))),
    ]),
  );
}

class _AuthAura extends StatelessWidget {
  const _AuthAura();
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: Stack(children: [
        Positioned(
          top: -130, right: -110,
          child: _blob(280, AppColors.accentPurple.withValues(alpha: 0.34)),
        ),
        Positioned(
          top: 40, left: -120,
          child: _blob(260, AppColors.neonCyan.withValues(alpha: 0.16)),
        ),
        Positioned(
          bottom: -120, left: 20,
          child: _blob(300, AppColors.accentStart.withValues(alpha: 0.16)),
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
