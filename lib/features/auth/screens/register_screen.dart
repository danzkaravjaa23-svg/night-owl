import 'package:flutter/material.dart';
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
              color: AppColors.accentStart))),
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
      body: SafeArea(
        child: Column(
          children: [
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
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Join the\nnight crew ✨', style: AppTextStyles.displayMd.copyWith(height: 1.2)),
                      const SizedBox(height: 8),
                      Text('UB-гийн шилдэг party-нуудад VIP эрх нээ',
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textSecondary)),
                      const SizedBox(height: 36),

                      _label('Name'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        autofillHints: const [AutofillHints.name],
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(hintText: 'Your name'),
                        validator: (v) => v!.isNotEmpty ? null : 'Required',
                      ),
                      const SizedBox(height: 20),

                      _label('Email'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.newUsername, AutofillHints.email],
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(hintText: 'your@email.com'),
                        validator: (v) => v!.contains('@') ? null : 'Valid email required',
                      ),
                      const SizedBox(height: 20),

                      _label('Password'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _pwCtrl,
                        obscureText: !_showPw,
                        autofillHints: const [AutofillHints.newPassword],
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Min 8 characters',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _showPw = !_showPw),
                            icon: Icon(
                              _showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: AppColors.textSecondary, size: 20,
                            ),
                          ),
                        ),
                        validator: (v) => v!.length >= 8 ? null : 'Min 8 characters',
                      ),
                      const SizedBox(height: 24),

                      // ToS checkbox
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _agreedTos = !_agreedTos),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: _agreedTos
                                    ? AppColors.accentStart
                                    : AppColors.bgSurface,
                                border: Border.all(
                                  color: _agreedTos
                                      ? AppColors.accentStart
                                      : AppColors.hairline2,
                                ),
                              ),
                              child: _agreedTos
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              children: [
                                Text('I agree to the ',
                                  style: AppTextStyles.bodySm),
                                GestureDetector(
                                  onTap: () => _showLegal(context, 'Terms of Service',
                                    'Night Owl UB-г ашигласнаар та манай үйлчилгээний нөхцөлийг хүлээн зөвшөөрч байна. Хууль бус контент, дарамт, спам хориотой. Бид дансыг түр болон бүрмөсөн хаах эрхтэй.'),
                                  child: Text('Terms of Service',
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppColors.accentStart)),
                                ),
                                Text(' and ', style: AppTextStyles.bodySm),
                                GestureDetector(
                                  onTap: () => _showLegal(context, 'Privacy Policy',
                                    'Бид таны мэдээллийг зөвхөн үйлчилгээгээ сайжруулах зорилгоор ашиглана. Таны өгөгдлийг гуравдагч этгээдэд зарахгүй. Та хүссэн үедээ дансаа устгаж болно.'),
                                  child: Text('Privacy Policy',
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppColors.accentStart)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!,
                          style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
                      ],

                      const SizedBox(height: 32),
                      GradientButton(
                        label: _loading ? 'Creating account...' : 'Create Account',
                        onPressed: _loading ? null : _register,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account? ',
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary)),
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Text('Sign In',
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
    );
  }

  Widget _label(String text) => Text(text,
    style: AppTextStyles.labelMd.copyWith(
      color: AppColors.textSecondary, letterSpacing: 0.8));
}
