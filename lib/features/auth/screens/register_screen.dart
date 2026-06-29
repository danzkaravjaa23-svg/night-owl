import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl    = TextEditingController();
  final _formKey   = GlobalKey<FormState>();
  bool _agreedTos  = false;
  bool _showPw     = false;
  bool _loading    = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _pwCtrl.dispose();
    super.dispose();
  }

  void _showLegal(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text(title, style: AppTextStyles.h3),
        content: Text(body, style: AppTextStyles.bodySm.copyWith(
          color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Хаах', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.neonCyan))),
        ],
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedTos) {
      setState(() => _error = 'Please agree to Terms of Service');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
        data: {'name': _nameCtrl.text.trim()},
      );
      if (res.user != null && mounted) {
        context.go(AppRoutes.setup);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
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
          const _AuthAura(),
          SafeArea(
            child: Column(
              children: [
                // Top bar — back only
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(children: [
                    _GlassBack(onTap: () => context.pop()),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 12, 26, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const _AuthGlyph(),
                            const SizedBox(width: 12),
                            Text('NIGHT OWL · UB', style: AppTextStyles.monoSm.copyWith(
                              letterSpacing: 3, color: AppColors.textTertiary)),
                          ]),
                          const SizedBox(height: 20),
                          Text('Join the night crew ✨',
                            style: AppTextStyles.displayMd.copyWith(height: 1.15)),
                          const SizedBox(height: 10),
                          Text('UB-гийн шилдэг party-нуудад VIP эрх нээ',
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary)),
                          const SizedBox(height: 18),

                          // Perk pills
                          Wrap(spacing: 8, runSpacing: 8, children: const [
                            _Pill(label: 'VIP эрх', color: AppColors.neonCyan),
                            _Pill(label: 'Live эвентүүд', color: AppColors.lime),
                            _Pill(label: 'Priority орц', color: AppColors.amber),
                          ]),
                          const SizedBox(height: 28),

                          const _FieldLabel('Нэр'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameCtrl,
                            autofillHints: const [AutofillHints.name],
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _dec(hint: 'Чиний нэр',
                              icon: Icons.person_outline_rounded),
                            validator: (v) => v!.isNotEmpty ? null : 'Required',
                          ),
                          const SizedBox(height: 18),

                          const _FieldLabel('И-мэйл'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.newUsername, AutofillHints.email],
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: _dec(hint: 'name@email.com',
                              icon: Icons.mail_outline_rounded),
                            validator: (v) => v!.contains('@') ? null : 'Valid email required',
                          ),
                          const SizedBox(height: 18),

                          const _FieldLabel('Нууц үг'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _pwCtrl,
                            obscureText: !_showPw,
                            autofillHints: const [AutofillHints.newPassword],
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
                            validator: (v) => v!.length >= 8 ? null : 'Min 8 characters',
                          ),
                          const SizedBox(height: 22),

                          // ToS checkbox
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => _agreedTos = !_agreedTos),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7),
                                    color: _agreedTos ? AppColors.neonCyan : AppColors.bgSurface,
                                    border: Border.all(
                                      color: _agreedTos ? AppColors.neonCyan : AppColors.hairline2),
                                    boxShadow: _agreedTos
                                        ? [BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.5),
                                            blurRadius: 12, spreadRadius: -2)]
                                        : [],
                                  ),
                                  child: _agreedTos
                                      ? const Icon(Icons.check_rounded, size: 15, color: AppColors.bgBase)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                                    GestureDetector(
                                      onTap: () => _showLegal(context, 'Үйлчилгээний нөхцөл',
                                        'Night Owl UB-г ашигласнаар та манай үйлчилгээний нөхцөлийг хүлээн зөвшөөрч байна. Хууль бус контент, дарамт, спам хориотой. Бид дансыг түр болон бүрмөсөн хаах эрхтэй.'),
                                      child: Text('Үйлчилгээний нөхцөл',
                                        style: AppTextStyles.bodySm.copyWith(color: AppColors.neonCyan)),
                                    ),
                                    Text(' болон ', style: AppTextStyles.bodySm),
                                    GestureDetector(
                                      onTap: () => _showLegal(context, 'Нууцлалын бодлого',
                                        'Бид таны мэдээллийг зөвхөн үйлчилгээгээ сайжруулах зорилгоор ашиглана. Таны өгөгдлийг гуравдагч этгээдэд зарахгүй. Та хүссэн үедээ дансаа устгаж болно.'),
                                      child: Text('Нууцлалын бодлогыг',
                                        style: AppTextStyles.bodySm.copyWith(color: AppColors.neonCyan)),
                                    ),
                                    Text(' зөвшөөрч байна', style: AppTextStyles.bodySm),
                                  ]),
                                ),
                              ),
                            ],
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            _ErrorBox(_error!),
                          ],

                          const SizedBox(height: 28),
                          GradientButton(
                            label: _loading ? 'Бүртгэж байна...' : 'Create Account',
                            onPressed: _loading ? null : _register,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 8, 26, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Бүртгэлтэй юу? ',
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Text('Нэвтрэх',
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

// ───────────────────────── auth UI bits ─────────────────────────

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

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18),
        blurRadius: 14, spreadRadius: -4)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(
        shape: BoxShape.circle, color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 6)])),
      const SizedBox(width: 7),
      Text(label, style: AppTextStyles.labelSm.copyWith(
        color: color, letterSpacing: 0)),
    ]),
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
  const _AuthGlyph();
  @override
  Widget build(BuildContext context) => Container(
    width: 48, height: 48,
    decoration: BoxDecoration(
      gradient: AppColors.accentGradient,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: AppColors.accentStart.withValues(alpha: 0.45),
          blurRadius: 22, spreadRadius: -3),
      ],
    ),
    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
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
  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z"/><path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"/><path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"/><path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571.001-.001.002-.001.003-.002l6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z"/></svg>''',
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
