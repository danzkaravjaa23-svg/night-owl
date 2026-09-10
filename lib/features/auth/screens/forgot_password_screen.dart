import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  // Back — шууд URL-ээр орж ирсэн үед pop хийх юмгүй тул login руу
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
  }

  Future<void> _send() async {
    // Enter дарж давхар илгээхээс сэргийлнэ
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      // redirectTo — сэргээх холбоос дарахад апп руу буцаж ирнэ.
      // Splash нь passwordRecovery event-ийг барьж шинэ нууц үгийн дэлгэц нээнэ.
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailCtrl.text.trim(),
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() => _error =
          m.contains('rate limit') || m.contains('too many')
              ? 'Хэт олон оролдлого. Түр хүлээгээд дахин оролдоно уу.'
              : 'Холбоос илгээж чадсангүй. И-мэйлээ шалгаад дахин оролдоно уу.');
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
                    const AuthGlyph(icon: Icons.lock_reset_rounded),
                    const SizedBox(height: 12),
                    Text('Нууц үг сэргээх', style: AppTextStyles.h1),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        'И-мэйлээ оруулбал бид нууц үг сэргээх холбоос илгээнэ.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textSecondary, height: 1.5)),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),

                // ── Доод (~70%) — шилэн bottom-sheet: форм / sent ──
                Expanded(
                  child: AuthEntrance(
                    index: 1,
                    child: _GlassSheet(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOut,
                        child: _sent ? _sentView() : _formView(),
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

  // ── И-мэйл оруулах форм — sheet дотор ──
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
                const FieldLabel('И-мэйл'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  style: authFieldStyle,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _send(),
                  decoration: authInputDec(
                    hint: 'name@email.com',
                    icon: Icons.mail_outline_rounded),
                  validator: (v) =>
                      v!.contains('@') ? null : 'И-мэйл хаяг буруу байна',
                ),
              ]),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthErrorBox(_error!),
          ],

          const SizedBox(height: 28),
          AuthEntrance(
            index: 3,
            child: GradientButton(
              label: _loading ? 'Илгээж байна...' : 'Холбоос илгээх',
              onPressed: _loading ? null : _send,
              borderRadius: 999,
              trailing: _loading
                  ? const BtnSpinner()
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Илгээгдсэн үеийн дэлгэц — sheet дотор ──
  Widget _sentView() => Center(
    key: const ValueKey('sent'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withValues(alpha: 0.14),
              boxShadow: [BoxShadow(
                color: AppColors.success.withValues(alpha: 0.25),
                blurRadius: 36, spreadRadius: -6)],
            ),
            child: const Icon(Icons.mark_email_read_outlined,
              color: AppColors.success, size: 40),
          ),
          const SizedBox(height: 24),
          Text('И-мэйлээ шалгаарай', style: AppTextStyles.h1,
            textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('Нууц үг сэргээх холбоос илгээлээ. Ирсэн и-мэйл дэх холбоос дээр дарна уу.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center),
          const SizedBox(height: 36),
          GradientButton(
            label: 'Нэвтрэх рүү буцах',
            borderRadius: 999,
            onPressed: _back,
          ),
        ],
      ),
    ),
  );
}

// ───────────────────────── forgot-only UI bits ─────────────────────────

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
