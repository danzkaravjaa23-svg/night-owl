import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart';
import '../widgets/auth_ui.dart';

class AuthLandingScreen extends StatefulWidget {
  const AuthLandingScreen({super.key});

  @override
  State<AuthLandingScreen> createState() => _AuthLandingScreenState();
}

class _AuthLandingScreenState extends State<AuthLandingScreen> {
  bool _gLoading = false;

  Future<void> _googleSignIn() async {
    setState(() => _gLoading = true);
    try {
      await signInWithGoogle();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Google-ээр нэвтрэхэд алдаа гарлаа. Дахин оролдоно уу.')));
      }
    } finally {
      if (mounted) setState(() => _gLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: SafeArea(child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Row(children: [
              Image.asset('assets/icons/night_owl_mark.png', width: 32, height: 36,
                errorBuilder: (_, __, ___) => const Icon(Icons.nightlight_round,
                  color: AppColors.silverLight, size: 28)),
              const SizedBox(width: 10),
              const Text('night owl', style: TextStyle(color: Colors.white,
                fontSize: 23, letterSpacing: -0.8, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Text('UB', style: TextStyle(
                color: AppColors.textSecondaryDark, fontSize: 9, letterSpacing: 1.2)),
            ]),
          ),
          SizedBox(height: 210, child: Stack(fit: StackFit.expand, children: [
            Image.asset('assets/images/tonight_city.png', fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.bgElevatedDark)),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0x000B0D17), AppColors.bgBaseDark], stops: [0.45, 1]))),
          ])),
          Padding(padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('ХОТ УНТААГҮЙ.', style: TextStyle(color: AppColors.silverLight,
                fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text('Оройг өөрийнхөөрөө.', style: TextStyle(
                color: Colors.white, fontSize: 36, height: 1.08,
                letterSpacing: -1.2, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              const Text('Дуртай газраа ол. Найзуудтайгаа холбогд.\nХотын шинэ хэмнэлийг хамт мэдэр.', style: TextStyle(
                color: AppColors.textSecondaryDark, fontSize: 14, height: 1.6)),
              const SizedBox(height: 28),
              GradientButton(label: 'Нэвтрэх', borderRadius: 16,
                trailing: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                onPressed: () => context.push(AppRoutes.login)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _gLoading ? null : _googleSignIn,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppColors.hairline2Dark),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_gLoading)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.silverLight))
                  else const GoogleMark(),
                  const SizedBox(width: 10),
                  Flexible(child: Text(_gLoading ? 'Түр хүлээнэ үү...' : 'Google-ээр үргэлжлүүлэх')),
                ])),
              const AppleSignInButton(onDark: true),
              const SizedBox(height: 16),
              TextButton(onPressed: () => context.push(AppRoutes.register),
                style: TextButton.styleFrom(foregroundColor: AppColors.silverLight),
                child: const Text('Анх удаа юу? Бүртгэл үүсгэх')),
            ])),
        ]),
      )),
    ),
  );
}
