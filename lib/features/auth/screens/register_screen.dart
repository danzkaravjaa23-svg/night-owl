import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';

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
  // Гар дээрх "Дараах" товч талбараас талбар руу шилжүүлнэ
  final _emailFocus = FocusNode();
  final _pwFocus    = FocusNode();
  bool _agreedTos  = false;
  bool _showPw     = false;
  bool _loading    = false;
  bool _gLoading   = false;
  bool _sent       = false; // и-мэйл баталгаажуулалт илгээгдсэн эсэх
  String? _error;

  // Зөвшөөрлийн текст доторх холбоосуудын товшилт таниулагч
  late final TapGestureRecognizer _tosTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _tosTap = TapGestureRecognizer()
      ..onTap = () => _showLegal(context, 'Үйлчилгээний нөхцөл',
          'Night Owl UB-г ашигласнаар та манай үйлчилгээний нөхцөлийг хүлээн '
          'зөвшөөрч байна. Хууль бус контент, дарамт, спам хориотой. '
          'Бид дансыг түр болон бүрмөсөн хаах эрхтэй.');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _showLegal(context, 'Нууцлалын бодлого',
          'Бид таны мэдээллийг зөвхөн үйлчилгээгээ сайжруулах зорилгоор '
          'ашиглана. Таны өгөгдлийг гуравдагч этгээдэд зарахгүй. '
          'Та хүссэн үедээ дансаа устгаж болно.');
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _pwCtrl.dispose();
    _emailFocus.dispose(); _pwFocus.dispose();
    _tosTap.dispose(); _privacyTap.dispose();
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

  // Нэвтрэх рүү — pop боломжгүй бол login руу шууд очно
  void _toLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
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
    // Enter дарж давхар илгээхээс сэргийлнэ
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedTos) {
      setState(() => _error = 'Үйлчилгээний нөхцөлийг зөвшөөрнө үү');
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
        data: {'name': _nameCtrl.text.trim()},
      );
      if (!mounted) return;
      if (res.user == null) {
        // Давхардсан и-мэйл г.м — Supabase обфускацилсан хариу буцаадаг
        setState(() => _error =
            'Бүртгэл үүсгэж чадсангүй. Энэ и-мэйл бүртгэлтэй байж магадгүй.');
      } else if (res.session == null) {
        // И-мэйл баталгаажуулалт идэвхтэй — нэвтрээгүй тул setup руу оруулахгүй
        setState(() => _sent = true);
      } else {
        context.go(AppRoutes.setup);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      setState(() {
        if (m.contains('already registered') || m.contains('already exists')) {
          _error = 'Энэ и-мэйл хаяг аль хэдийн бүртгэлтэй байна.';
        } else if (m.contains('password')) {
          _error = 'Нууц үг хэтэрхий сул байна. Өөр нууц үг сонгоно уу.';
        } else if (m.contains('rate limit') || m.contains('too many')) {
          _error = 'Хэт олон оролдлого. Түр хүлээгээд дахин оролдоно уу.';
        } else {
          _error = 'Бүртгэхэд алдаа гарлаа. Дахин оролдоно уу.';
        }
      });
    } catch (e) {
      // Сүлжээний алдаа зэрэг — чимээгүй унагаахгүй
      if (mounted) {
        setState(() => _error = 'Бүртгэхэд алдаа гарлаа. Сүлжээгээ шалгана уу.');
      }
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
          // ── Futurist Nightscape aura — login-той ижил гэр бүл ──
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
                const SizedBox(height: 14),
                AuthEntrance(
                  child: Column(children: [
                    const _RegisterGlyph(),
                    const SizedBox(height: 12),
                    Text('Шөнийн багт нэгдээрэй ✨', style: AppTextStyles.h1),
                    const SizedBox(height: 6),
                    Text('UB-гийн шилдэг party-нуудад VIP эрх нээ',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary)),
                  ]),
                ),
                const SizedBox(height: 18),

                // ── Доод (~70%) — шилэн bottom-sheet: форм / sent + footer ──
                Expanded(
                  child: AuthEntrance(
                    index: 2,
                    child: _GlassSheet(
                      child: Column(
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              switchInCurve: Curves.easeOut,
                              child: _sent ? _sentView() : _formView(),
                            ),
                          ),
                          // Footer — sheet-ийн доод захад бэхлэгдсэн
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Бүртгэлтэй юу? ',
                                  style: AppTextStyles.bodyMd.copyWith(
                                    color: AppColors.textSecondary)),
                                TapScale(
                                  onTap: _toLogin,
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── И-мэйл баталгаажуулах хүсэлт илгээгдсэн үеийн дэлгэц (sheet дотор) ──
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
          Text(
            '${_emailCtrl.text.trim()} хаяг руу баталгаажуулах холбоос илгээлээ. '
            'Холбоос дээр дараад бүртгэлээ баталгаажуулна уу.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center),
          const SizedBox(height: 36),
          GradientButton(
            label: 'Нэвтрэх рүү очих',
            borderRadius: 999,
            onPressed: _toLogin,
          ),
        ],
      ),
    ),
  );

  // ── Бүртгэлийн үндсэн форм — sheet дотор гүйлгэгдэнэ ──
  Widget _formView() => SingleChildScrollView(
    key: const ValueKey('form'),
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthEntrance(
            index: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Нэр'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  autofillHints: const [AutofillHints.name],
                  style: authFieldStyle,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                  decoration: authInputDec(hint: 'Чиний нэр',
                    icon: Icons.person_outline_rounded),
                  validator: (v) => v!.trim().isNotEmpty ? null : 'Заавал бөглөнө',
                ),
              ]),
          ),
          const SizedBox(height: 18),

          AuthEntrance(
            index: 4,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('И-мэйл'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.newUsername, AutofillHints.email],
                  style: authFieldStyle,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _pwFocus.requestFocus(),
                  decoration: authInputDec(hint: 'name@email.com',
                    icon: Icons.mail_outline_rounded),
                  validator: (v) => v!.contains('@') ? null : 'И-мэйл хаяг буруу байна',
                ),
              ]),
          ),
          const SizedBox(height: 18),

          AuthEntrance(
            index: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Нууц үг'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pwCtrl,
                  focusNode: _pwFocus,
                  obscureText: !_showPw,
                  autofillHints: const [AutofillHints.newPassword],
                  style: authFieldStyle,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
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
          const SizedBox(height: 22),

          // ToS checkbox — бүтэн мөр нь toggle (хаана ч дарахад асна/унтарна),
          // мөрийн өндөр 48px-ээс багагүй, холбоос бүр өөрийн 44px талбайтай
          AuthEntrance(
            index: 6,
            child: TapScale(
              onTap: () => setState(() => _agreedTos = !_agreedTos),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  AnimatedContainer(
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
                  const SizedBox(width: 11),
                  // Хууль зүйн зөвшөөрөл — урсгал текст доторх холбоос
                  // (стандарт бүртгэлийн загвар). Мөр бүхэлдээ чагтыг
                  // сэлгэдэг тул холбоосуудад 44px хайрцаг шаардлагагүй;
                  // тэгвэл 420px дээр блок хоёр дахин өндөрсөнө.
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Үйлчилгээний нөхцөл',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.neonCyan,
                            fontWeight: FontWeight.w600),
                          recognizer: _tosTap),
                        TextSpan(text: ' болон ', style: AppTextStyles.bodySm),
                        TextSpan(text: 'Нууцлалын бодлогыг',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.neonCyan,
                            fontWeight: FontWeight.w600),
                          recognizer: _privacyTap),
                        TextSpan(text: ' зөвшөөрч байна',
                          style: AppTextStyles.bodySm),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthErrorBox(_error!),
          ],

          const SizedBox(height: 24),
          AuthEntrance(
            index: 7,
            child: GradientButton(
              label: _loading ? 'Бүртгэж байна...' : 'Бүртгэл үүсгэх',
              onPressed: _loading ? null : _register,
              borderRadius: 999,
              trailing: _loading
                  ? const BtnSpinner()
                  : const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 19),
            ),
          ),
          const SizedBox(height: 20),
          const AuthEntrance(index: 8, child: OrDivider()),
          const SizedBox(height: 20),
          AuthEntrance(
            index: 9,
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
  );
}

// ───────────────────────── register-only UI bits ─────────────────────────

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

class _RegisterGlyph extends StatelessWidget {
  const _RegisterGlyph();
  @override
  Widget build(BuildContext context) => Container(
    width: 56, height: 56,
    decoration: BoxDecoration(
      gradient: AppColors.accentGradient,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: AppColors.accentStart.withValues(alpha: 0.45),
          blurRadius: 22, spreadRadius: -3),
      ],
    ),
    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
  );
}
