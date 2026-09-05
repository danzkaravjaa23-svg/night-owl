import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/mesh_gradient.dart';
import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';

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
  bool _gLoading   = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  // Back — шууд URL-ээр орж ирсэн үед pop хийх юмгүй тул landing руу
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.authLanding);
    }
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
      if (!mounted) return;
      // Supabase-ийн тодорхой алдааг ойлгомжтой болгох
      final m = e.message.toLowerCase();
      setState(() {
        if (m.contains('invalid login') || m.contains('credentials')) {
          _error = 'И-мэйл эсвэл нууц үг буруу байна.';
        } else if (m.contains('email not confirmed') || m.contains('confirm')) {
          _error = 'И-мэйл хаягаа баталгаажуулаагүй байна.';
        } else if (m.contains('rate limit') || m.contains('too many')) {
          _error = 'Хэт олон оролдлого. Түр хүлээгээд дахин оролдоно уу.';
        } else {
          _error = 'Нэвтрэхэд алдаа гарлаа. Дахин оролдоно уу.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Нэвтрэхэд алдаа гарлаа. Сүлжээгээ шалгана уу.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Google OAuth — web дээр бүтэн хуудас redirect хийнэ
  Future<void> _googleSignIn() async {
    setState(() { _gLoading = true; _error = null; });
    try {
      await signInWithGoogle();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Google-ээр нэвтрэхэд алдаа гарлаа. Дахин оролдоно уу.');
      }
    } finally {
      if (mounted) setState(() => _gLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        children: [
          // ── Futurist Nightscape aura ──
          const AuthAura(),
          SafeArea(
            child: Column(
              children: [
                // ── Дээд hero (~30%) — back chip + owl mini + мэндчилгээ ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Row(children: [
                    GlassBack(onTap: _back),
                    const Spacer(),
                    Text('NIGHT OWL', style: AppTextStyles.monoSm.copyWith(
                      letterSpacing: 3, color: AppColors.textTertiary)),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ]),
                ),
                const SizedBox(height: 16),
                AuthEntrance(
                  child: Column(children: [
                    const OwlLogoMark(size: 56),
                    const SizedBox(height: 12),
                    Text('Тавтай морил 👋', style: AppTextStyles.h1),
                    const SizedBox(height: 6),
                    Text('Дахин нэвтрээд party-даа эргэн нэгдээрэй',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary)),
                  ]),
                ),
                const SizedBox(height: 22),

                // ── Доод (~70%) — шилэн bottom-sheet: форм + CTA + Google ──
                Expanded(
                  child: AuthEntrance(
                    index: 1,
                    child: _GlassSheet(
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Email
                                    AuthEntrance(
                                      index: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const FieldLabel('И-мэйл'),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _emailCtrl,
                                            keyboardType: TextInputType.emailAddress,
                                            autofillHints: const [AutofillHints.username, AutofillHints.email],
                                            style: const TextStyle(color: AppColors.textPrimary),
                                            decoration: authInputDec(
                                              hint: 'name@email.com',
                                              icon: Icons.mail_outline_rounded),
                                            validator: (v) =>
                                                v!.contains('@') ? null : 'И-мэйл хаяг буруу байна',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),

                                    // Password
                                    AuthEntrance(
                                      index: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const FieldLabel('Нууц үг'),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: _pwCtrl,
                                            obscureText: !_showPw,
                                            autofillHints: const [AutofillHints.password],
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
                                            // Нэвтрэхэд зөвхөн хоосон эсэхийг шалгана —
                                            // хуучин богино нууц үгтэй хэрэглэгчийг түгжихгүй
                                            validator: (v) =>
                                                v!.isNotEmpty ? null : 'Нууц үгээ оруулна уу',
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (_error != null) ...[
                                      const SizedBox(height: 16),
                                      AuthErrorBox(_error!),
                                    ],

                                    const SizedBox(height: 6),
                                    AuthEntrance(
                                      index: 4,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () => context.push(AppRoutes.forgotPassword),
                                          child: Text('Нууц үг мартсан уу?',
                                            style: AppTextStyles.labelSm.copyWith(
                                              color: AppColors.neonCyan, letterSpacing: 0)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    AuthEntrance(
                                      index: 5,
                                      child: GradientButton(
                                        label: _loading ? 'Нэвтрэж байна...' : 'Нэвтрэх',
                                        onPressed: _loading ? null : _signIn,
                                        borderRadius: 999,
                                        trailing: _loading
                                            ? const BtnSpinner()
                                            : const Icon(Icons.arrow_forward_rounded,
                                                color: Colors.white, size: 19),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    const AuthEntrance(index: 6, child: OrDivider()),
                                    const SizedBox(height: 20),
                                    AuthEntrance(
                                      index: 7,
                                      child: _GhostBtn(
                                        label: _gLoading
                                            ? 'Түр хүлээнэ үү...'
                                            : 'Google-ээр үргэлжлүүлэх',
                                        leading: _gLoading
                                            ? const SizedBox(width: 16, height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: AppColors.textSecondary))
                                            : const GoogleMark(),
                                        onTap: _gLoading ? null : _googleSignIn,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Footer — sheet-ийн доод захад бэхлэгдсэн
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Шинэ хэрэглэгч үү? ',
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.textSecondary)),
                                TapScale(
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

// ───────────────────────── login-only UI bits ─────────────────────────

/// Шилэн bottom-sheet бүрхүүл — дээд radius 28, bgElevated @0.85, grabber.
class _GlassSheet extends StatelessWidget {
  final Widget child;
  const _GlassSheet({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppColors.bgElevated.withValues(alpha: 0.85),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      border: Border.all(color: AppColors.hairline2),
      boxShadow: AppColors.shadowDock,
    ),
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Column(children: [
        const SizedBox(height: 10),
        // Grabber — bottom-sheet мэдрэмж
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.hairline2,
            borderRadius: BorderRadius.circular(999)),
        ),
        Expanded(child: child),
      ]),
    ),
  );
}

/// Pill хэлбэрт glass outline товч (Google г.м хоёрдогч үйлдэл).
class _GhostBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  const _GhostBtn({required this.label, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    width: double.infinity,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Text(label, style: AppTextStyles.btn.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}
