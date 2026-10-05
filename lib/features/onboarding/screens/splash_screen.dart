import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart'
    show pendingPasswordRecovery, SupabaseService;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StreamSubscription<AuthState>? _authSub;
  bool _recovery = false; // нууц үг сэргээх холбоосоор орж ирсэн эсэх

  @override
  void initState() {
    super.initState();
    // Нууц үг сэргээх и-мэйлийн холбоосоор ирвэл supabase_flutter
    // token-ыг сольж passwordRecovery event гаргана — түүнийг барина
    _authSub = SupabaseService.authStream.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) {
        _recovery = true;
      }
    });
    // Google/OAuth-оос буцаж ирсэн бол (URL-д code/token) — шууд authLanding руу
    // үсрэхгүй хүлээнэ. Session тогтмогц router-ийн AuthGate feed/setup рүү аваачна.
    final hasOAuth = _hasAuthCallback();
    Future.delayed(Duration(milliseconds: hasOAuth ? 4000 : 1800), () {
      if (!mounted) return;
      // OAuth callback амжилттай бол redirect аль хэдийн зөөсөн — давхар үсрэхгүй
      if (hasOAuth && Supabase.instance.client.auth.currentSession != null) {
        return;
      }
      _navigate();
    });
  }

  // URL-д OAuth callback параметр (Google-ээс буцсан) байгаа эсэх
  bool _hasAuthCallback() {
    final u = Uri.base.toString();
    return u.contains('code=') ||
        u.contains('access_token') ||
        u.contains('token_hash=') ||
        u.contains('error=') ||
        u.contains('error_description');
  }

  Future<void> _navigate() async {
    if (!mounted) return;

    // 1) Нууц үг сэргээх flow — шинэ нууц үгийн дэлгэц нээнэ
    if (_recovery || pendingPasswordRecovery) {
      context.go(AppRoutes.resetPassword);
      return;
    }

    // 2) Хадгалагдсан session байвал шууд апп руу —
    //    нэвтэрсэн хэрэглэгчийг дахин sign-in руу оруулахгүй
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      var hasProfile = true;
      try {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('username')
            .eq('id', session.user.id)
            .maybeSingle();
        hasProfile = (data?['username'] as String? ?? '').isNotEmpty;
      } catch (_) {
        // Уншиж чадаагүй бол feed рүү — тэнд өөрөө шийднэ
      }
      if (!mounted) return;
      // Шинэ (жишээ нь Google-ээр орсон) хэрэглэгч профайлгүй бол setup руу
      context.go(hasProfile ? AppRoutes.feed : AppRoutes.setup);
      return;
    }

    // 3) Анхны орох урсгал
    final prefs = await SharedPreferences.getInstance();
    final hasOnboarded = prefs.getBool('onboarded') ?? false;
    final locale = prefs.getString('locale');
    if (!mounted) return;
    if (locale == null) {
      context.go(AppRoutes.langSelect);
    } else if (!hasOnboarded) {
      context.go('${AppRoutes.onboarding}?slide=1');
    } else {
      context.go(AppRoutes.authLanding);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0B0D17),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -.28),
              radius: 1.1,
              colors: [Color(0xFF211737), Color(0xFF0B0D17)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: AppEntrance(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          NightOwlMark(size: 124),
                          SizedBox(height: 20),
                          NightOwlLogoText(fontSize: 36, onDark: true),
                          SizedBox(height: 14),
                          Text('Оройн газрууд. Өөрийн хүмүүс.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Color(0xFFB6A4FF),
                                  fontSize: 14,
                                  height: 1.5)),
                          SizedBox(height: 48),
                          OwlLoading(
                              size: 44,
                              onDark: true,
                              message: 'Night Owl-ийг нээж байна'),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );
}
