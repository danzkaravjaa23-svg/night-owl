import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/auth_callback.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/gradient_button.dart';
import '../widgets/auth_ui.dart';
import '../widgets/password_form.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = false;
  String? _sentTo;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _back() {
    if (_loading) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
  }

  Future<void> _send() async {
    if (_loading || !_form.currentState!.validate()) return;
    final email = _email.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(email,
              redirectTo: oauthRedirectUrl(isWeb: kIsWeb, baseUri: Uri.base))
          .timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _sentTo = email);
    } on AuthException catch (error) {
      if (!mounted) return;
      final limited = error.statusCode == '429' ||
          error.code == 'over_email_send_rate_limit';
      setState(() => _error = limited
          ? 'Хэт олон оролдлого. Түр хүлээгээд дахин оролдоно уу.'
          : 'Холбоос илгээснийг баталж чадсангүй. Имэйлээ шалгаад дахин оролдоно уу.');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Хариу хүлээж чадсангүй. Имэйл тань ирсэн эсэхийг шалгаж, шаардлагатай бол дахин оролдоно уу.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_loading,
        child: AuthFormScaffold(
          title: 'Нууц үг сэргээх',
          description: 'Бүртгэлтэй имэйл хаягтаа сэргээх холбоос авна уу.',
          icon: _sentTo == null
              ? Icons.lock_reset_rounded
              : Icons.mark_email_read_outlined,
          onBack: _loading ? null : _back,
          child: _sentTo != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Имэйлээ шалгаарай',
                        style: AppTextStyles.h2, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text(
                        '$_sentTo хаяг бүртгэлтэй бол сэргээх холбоос очно. Ирсэн имэйл болон спам хавтсаа шалгана уу.',
                        style: AppTextStyles.bodyMd.copyWith(
                            color: AppColors.textSecondary, height: 1.5),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    GradientButton(
                        label: 'Нэвтрэх рүү буцах', onPressed: _back),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => setState(() => _sentTo = null),
                        child: const Text('Имэйл хаягаа өөрчлөх')),
                  ],
                )
              : AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const FieldLabel('Имэйл'),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const ValueKey('recovery-email'),
                          controller: _email,
                          enabled: !_loading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          style: authFieldStyle,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _send(),
                          decoration: authInputDec(
                              hint: 'name@email.com',
                              icon: Icons.mail_outline_rounded),
                          validator: (value) => Validators.email(value?.trim()),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                              liveRegion: true, child: AuthErrorBox(_error!)),
                        ],
                        const SizedBox(height: 24),
                        GradientButton(
                          key: const ValueKey('send-recovery'),
                          label: 'Холбоос илгээх',
                          busy: _loading,
                          onPressed: _send,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      );
}
