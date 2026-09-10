import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text_styles.dart';

/// Нэвтрэлтийн дэлгэцүүдийн хуваалцсан UI хэсгүүд.
/// login/register/forgot дээр давхардаж байсан кодыг нэг дор нэгтгэв.

// ── Нууц үгийн доод урт — бүх auth дэлгэцэд нэг стандарт ──
const int kPasswordMinLength = 8;

// ── Google OAuth — жинхэнэ нэвтрэлт (web: одоогийн origin руу буцна) ──
Future<void> signInWithGoogle() async {
  await Supabase.instance.client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: kIsWeb ? Uri.base.origin : null,
  );
}

/// Талбарт бичигдэх текстийн нэгдсэн хэв маяг — бүх auth талбар үүнийг
/// хэрэглэнэ (өмнө нь талбар бүр түүхий TextStyle дамжуулж, төрлийн
/// шатлалаас гардаг байсан).
TextStyle get authFieldStyle =>
    AppTextStyles.bodyLg.copyWith(color: AppColors.textPrimary);

// ── Талбарын нийтлэг чимэглэл — шилэн fill, фокус үед cyan hairline ──
InputDecoration authInputDec({
  required String hint, required IconData icon, Widget? suffix,
}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: AppRadii.mdR,
    borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    // Hint нь бичсэн текстийн хэмжээтэй ижил — зөвхөн өнгөөр ялгарна
    hintStyle: AppTextStyles.bodyLg.copyWith(color: AppColors.textSecondary),
    prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.bgElevated.withValues(alpha: 0.70),
    enabledBorder: b(AppColors.hairline),
    focusedBorder: b(AppColors.neonCyan.withValues(alpha: 0.75), 1.2),
    errorBorder: b(AppColors.error.withValues(alpha: 0.55)),
    focusedErrorBorder: b(AppColors.error.withValues(alpha: 0.8), 1.2),
  );
}

/// Орох анимаци — fade + 12px дээш гулсалт, index бүрт 40ms шатлана.
class AuthEntrance extends StatelessWidget {
  final int index;
  final Widget child;
  const AuthEntrance({super.key, this.index = 0, required this.child});
  @override
  Widget build(BuildContext context) {
    final delay = index * 40;
    final total = 220 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOut),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

// ── Ачаалж буй товчны spinner (GradientButton-ы trailing) ──
class BtnSpinner extends StatelessWidget {
  const BtnSpinner({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 16, height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );
}

/// Дарахад агшиж (0.96), hover дээр заагч гардаг tap wrapper — web мэдрэмж.
class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const TapScale({super.key, required this.child, this.onTap});
  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap != null
        ? SystemMouseCursors.click : MouseCursor.defer,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    ),
  );
}

class FieldLabel extends StatelessWidget {
  final String label;
  const FieldLabel(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2),
    // Формын шошго — өгүүлбэрийн бичиглэл, уншигдахуйц контраст
    child: Text(label, style: AppTextStyles.labelSm.copyWith(
      color: AppColors.textSecondary, letterSpacing: 0.4)),
  );
}

class GlassBack extends StatelessWidget {
  final VoidCallback onTap;
  const GlassBack({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
    onTap: onTap,
    // Шилэн товч — web дээр BackdropFilter удаан тул хатуу glass өнгө
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.hairline2),
      ),
      child: const Icon(Icons.chevron_left_rounded,
        color: AppColors.textPrimary, size: 24),
    ),
  );
}

class AuthGlyph extends StatelessWidget {
  final IconData icon;
  const AuthGlyph({super.key, required this.icon});
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
    // Шилэн medallion — blur-гүй glass (web perf)
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Icon(icon, color: AppColors.neonCyan, size: 26),
    ),
  );
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(color: AppColors.hairline)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text('ЭСВЭЛ', style: AppTextStyles.monoSm.copyWith(letterSpacing: 2)),
    ),
    const Expanded(child: Divider(color: AppColors.hairline)),
  ]);
}

class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});

  static const String _svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.611 20.083H42V20H24v8h11.303c-1.649 4.657-6.08 8-11.303 8-6.627 0-12-5.373-12-12s5.373-12 12-12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 12.955 4 4 12.955 4 24s8.955 20 20 20 20-8.955 20-20c0-1.341-.138-2.65-.389-3.917z"/><path fill="#FF3D00" d="M6.306 14.691l6.571 4.819C14.655 15.108 18.961 12 24 12c3.059 0 5.842 1.154 7.961 3.039l5.657-5.657C34.046 6.053 29.268 4 24 4 16.318 4 9.656 8.337 6.306 14.691z"/><path fill="#4CAF50" d="M24 44c5.166 0 9.86-1.977 13.409-5.192l-6.19-5.238C29.211 35.091 26.715 36 24 36c-5.202 0-9.619-3.317-11.283-7.946l-6.522 5.025C9.505 39.556 16.227 44 24 44z"/><path fill="#1976D2" d="M43.611 20.083H42V20H24v8h11.303c-.792 2.237-2.231 4.166-4.087 5.571.001-.001.002-.001.003-.002l6.19 5.238C36.971 39.205 44 34 44 24c0-1.341-.138-2.65-.389-3.917z"/></svg>';

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    _svg, width: 20, height: 20,
  );
}

class AuthErrorBox extends StatelessWidget {
  final String message;
  const AuthErrorBox(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      // Зөөлөн улаан glow — анхааруулга мэдрэгдэхүйц ч түрэмгий биш
      boxShadow: [BoxShadow(color: AppColors.error.withValues(alpha: 0.14),
        blurRadius: 18, spreadRadius: -6)],
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: AppColors.error, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(message,
        style: AppTextStyles.bodySm.copyWith(
          color: AppColors.error, height: 1.35))),
    ]),
  );
}

class AuthAura extends StatelessWidget {
  const AuthAura({super.key});
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
