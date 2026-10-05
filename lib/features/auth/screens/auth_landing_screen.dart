import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/owl_loading.dart';
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
            content:
                Text('Google-ээр нэвтрэхэд алдаа гарлаа. Дахин оролдоно уу.')));
      }
    } finally {
      if (mounted) setState(() => _gLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppColors.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: AppColors.bgBase,
          body: SafeArea(
              child: SingleChildScrollView(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
                            child:
                                LayoutBuilder(builder: (context, constraints) {
                              final brand = Row(children: [
                                Image.asset('assets/icons/night_owl_mark.png',
                                    width: 32,
                                    height: 36,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.nightlight_round,
                                        color: AppColors.silverLight,
                                        size: 28)),
                                const SizedBox(width: 10),
                                Flexible(
                                    child: Text('night owl',
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 23,
                                            letterSpacing: -0.8,
                                            fontWeight: FontWeight.w700))),
                              ]);
                              final city = Text('Улаанбаатар',
                                  style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 10,
                                      letterSpacing: 0.3));
                              if (MediaQuery.textScalerOf(context).scale(23) >
                                  28) {
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      brand,
                                      const SizedBox(height: 6),
                                      city
                                    ]);
                              }
                              return Row(children: [
                                Expanded(child: brand),
                                const SizedBox(width: 12),
                                city
                              ]);
                            }),
                          ),
                          SizedBox(
                              height: 210,
                              child: Stack(fit: StackFit.expand, children: [
                                Image.asset('assets/images/tonight_city.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(
                                            color: AppColors.bgElevatedDark)),
                                DecoratedBox(
                                    decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                      const Color(0x000B0D17),
                                      AppColors.bgBase
                                    ],
                                            stops: const [
                                      0.45,
                                      1
                                    ]))),
                              ])),
                          Padding(
                              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text('САЙХАН ОРОЙ. ХАМТДАА.',
                                        style: TextStyle(
                                            color: AppColors.silver,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 2)),
                                    const SizedBox(height: 12),
                                    Text('Оройг өөрийнхөөрөө.',
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 36,
                                            height: 1.08,
                                            letterSpacing: -1.2,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 14),
                                    Text(
                                        'Улаанбаатарын газруудыг газрын зураг дээрээс ол. '
                                        'Зураг, story-гоо хуваалцаж, найзуудтайгаа холбоотой бай.',
                                        style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 14,
                                            height: 1.6)),
                                    const SizedBox(height: 12),
                                    Text('Үнэгүй бүртгэл. Үнэгүй хэрэглээ.',
                                        style: TextStyle(
                                            color: AppColors.silver,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 28),
                                    GradientButton(
                                        label: 'Имэйлээр нэвтрэх',
                                        borderRadius: 16,
                                        trailing: const Icon(
                                            Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                            size: 18),
                                        onPressed: () =>
                                            context.push(AppRoutes.login)),
                                    const SizedBox(height: 12),
                                    OutlinedButton(
                                        onPressed:
                                            _gLoading ? null : _googleSignIn,
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppColors.textPrimary,
                                            minimumSize:
                                                const Size.fromHeight(52),
                                            side: BorderSide(
                                                color: AppColors.hairline2),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16))),
                                        child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (_gLoading)
                                                const OwlLoading(
                                                    size: 24,
                                                    compact: true,
                                                    message:
                                                        'Google-ээр нэвтэрч байна')
                                              else
                                                const GoogleMark(),
                                              const SizedBox(width: 10),
                                              Flexible(
                                                  child: Text(_gLoading
                                                      ? 'Түр хүлээнэ үү...'
                                                      : 'Google-ээр үргэлжлүүлэх')),
                                            ])),
                                    const AppleSignInButton(),
                                    const SizedBox(height: 16),
                                    TextButton(
                                        onPressed: () =>
                                            context.push(AppRoutes.register),
                                        style: TextButton.styleFrom(
                                            foregroundColor: AppColors.silver),
                                        child: const Text('Шинээр бүртгүүлэх')),
                                  ])),
                        ]))),
          )),
        ),
      );
}
