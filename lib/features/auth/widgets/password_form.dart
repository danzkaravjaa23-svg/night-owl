import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/gradient_button.dart';
import 'auth_ui.dart';

/// Scrolls the whole form when the keyboard or large text reduces available space.
class AuthFormScaffold extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onBack;
  final Widget child;

  const AuthFormScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onBack,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Stack(fit: StackFit.expand, children: [
          const AuthAura(),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(children: [
                    Row(children: [
                      IconButton(
                        onPressed: onBack,
                        tooltip: 'Буцах',
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text('NIGHT OWL',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.monoSm.copyWith(
                                letterSpacing: 3,
                                color: AppColors.textTertiary)),
                      ),
                      const SizedBox(width: 48),
                    ]),
                    const SizedBox(height: 20),
                    AuthGlyph(icon: icon),
                    const SizedBox(height: 20),
                    Text(title,
                        textAlign: TextAlign.center, style: AppTextStyles.h1),
                    const SizedBox(height: 10),
                    Text(description,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMd.copyWith(
                            color: AppColors.textSecondary, height: 1.5)),
                    const SizedBox(height: 28),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.hairline2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: child,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// One password policy, accessible visibility control and submission guard.
class PasswordForm extends StatefulWidget {
  final bool busy;
  final String? error;
  final ValueChanged<String> onSubmit;

  const PasswordForm({
    super.key,
    required this.busy,
    required this.error,
    required this.onSubmit,
  });

  @override
  State<PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<PasswordForm> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _confirmFocus = FocusNode();
  bool _visible = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    widget.onSubmit(_password.text);
  }

  @override
  Widget build(BuildContext context) => AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Шинэ нууц үг'),
              const SizedBox(height: 8),
              Semantics(
                  label: 'Шинэ нууц үг',
                  child: TextFormField(
                    key: const ValueKey('new-password'),
                    controller: _password,
                    enabled: !widget.busy,
                    obscureText: !_visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.newPassword],
                    style: authFieldStyle,
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                    decoration: authInputDec(
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        tooltip: _visible
                            ? 'Нууц үгийг нуух'
                            : 'Нууц үгийг харуулах',
                        onPressed: widget.busy
                            ? null
                            : () => setState(() => _visible = !_visible),
                        icon: Icon(_visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                      ),
                    ),
                    validator: Validators.password,
                  )),
              const SizedBox(height: 8),
              Text('Хамгийн багадаа $kPasswordMinLength тэмдэгт.',
                  style: AppTextStyles.bodyXs
                      .copyWith(color: AppColors.textSecondary, height: 1.5)),
              const SizedBox(height: 20),
              const FieldLabel('Нууц үг давтах'),
              const SizedBox(height: 8),
              Semantics(
                  label: 'Нууц үг давтах',
                  child: TextFormField(
                    key: const ValueKey('confirm-password'),
                    controller: _confirm,
                    focusNode: _confirmFocus,
                    enabled: !widget.busy,
                    obscureText: !_visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.newPassword],
                    style: authFieldStyle,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: authInputDec(
                        hint: '••••••••', icon: Icons.lock_outline_rounded),
                    validator: (value) =>
                        Validators.confirmPassword(value, _password.text),
                  )),
              if (widget.error != null) ...[
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: AuthErrorBox(widget.error!)),
              ],
              const SizedBox(height: 24),
              GradientButton(
                key: const ValueKey('save-password'),
                label: 'Нууц үг шинэчлэх',
                busy: widget.busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      );
}
