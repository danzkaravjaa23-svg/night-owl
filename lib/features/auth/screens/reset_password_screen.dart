import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart' show passwordJustReset;
import '../widgets/auth_ui.dart';

/// Нууц үг сэргээх холбоосоор ирсэн хэрэглэгчид шинэ нууц үг тавих дэлгэц.
/// Router (AuthGate.recovery) нь token_hash холбоос/passwordRecovery event үед
/// энэ дэлгэц рүү автоматаар аваачна.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pwCtrl      = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey     = GlobalKey<FormState>();
  // Гар дээрх "Дараах" товч талбараас талбар руу шилжүүлнэ
  final _confirmFocus = FocusNode();
  bool _showPw   = false;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // Back — сэргээх session-ыг хааж login руу буцна. signOut хийхгүй бол
  // router (AuthGate.recovery) хэрэглэгчийг энэ дэлгэц рүү буцаана.
  Future<void> _back() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    authGate.finishRecovery();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  Future<void> _save() async {
    // Enter дарж давхар илгээхээс сэргийлнэ
    if (_loading) return;
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
      // Аюулгүй байдал: сэргээх session-ыг хаагаад шинэ нууц үгээрээ
      // дахин нэвтрүүлнэ (бусад апп шиг). signOut → AuthGate.recovery унтарна.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      passwordJustReset = true;
      authGate.finishRecovery();
      if (!mounted) return;
      context.go(AppRoutes.login);
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
          // ── Futurist Nightscape aura — бусад auth дэлгэцтэй ижил ──
          const AuthAura(),
          SafeArea(
            child: Column(
              children: [
                // ── Дээд hero (~30%) — back chip + glyph + гарчиг ──
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
                    const AuthGlyph(icon: Icons.password_rounded),
                    const SizedBox(height: 12),
                    Text('Шинэ нууц үг', style: AppTextStyles.h1),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        'Дансандаа шинэ нууц үг тохируулна уу.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textSecondary, height: 1.5)),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),

                // ── Доод (~70%) — шилэн bottom-sheet: форм ──
                Expanded(
                  child: AuthEntrance(
                    index: 1,
                    child: _GlassSheet(child: _formView()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Шинэ нууц үгийн форм — sheet дотор ──
  Widget _formView() => SingleChildScrollView(
    key: const ValueKey('form'),
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthEntrance(
            index: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Шинэ нууц үг'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pwCtrl,
                  obscureText: !_showPw,
                  autofillHints: const [AutofillHints.newPassword],
                  style: authFieldStyle,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
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
              ]),
          ),
          const SizedBox(height: 18),

          AuthEntrance(
            index: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Нууц үг давтах'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmCtrl,
                  focusNode: _confirmFocus,
                  obscureText: !_showPw,
                  autofillHints: const [AutofillHints.newPassword],
                  style: authFieldStyle,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: authInputDec(
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded),
                  validator: (v) => v == _pwCtrl.text
                      ? null : 'Нууц үг таарахгүй байна',
                ),
              ]),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthErrorBox(_error!),
          ],

          const SizedBox(height: 28),
          AuthEntrance(
            index: 4,
            child: GradientButton(
              label: _loading ? 'Хадгалж байна...' : 'Нууц үг шинэчлэх',
              onPressed: _loading ? null : _save,
              borderRadius: 999,
              trailing: _loading
                  ? const BtnSpinner()
                  : const Icon(Icons.check_rounded,
                      color: Colors.white, size: 19),
            ),
          ),
        ],
      ),
    ),
  );
}

// ───────────────────────── reset-only UI bits ─────────────────────────

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
