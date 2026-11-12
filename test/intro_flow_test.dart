import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/router/app_router.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/features/auth/screens/auth_landing_screen.dart';
import 'package:night_owl_ub/features/onboarding/screens/onboarding_screen.dart';
import 'package:night_owl_ub/features/onboarding/screens/splash_screen.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpIntro(
      WidgetTester tester, GoRouter router, Brightness brightness) async {
    AppColors.isDarkMode = brightness == Brightness.dark;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AppColors.isDarkMode = true;
      router.dispose();
    });
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!)));
    await tester.pump(const Duration(milliseconds: 350));
  }

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('beginning copy and email/register actions work in $brightness',
        (tester) async {
      final router = GoRouter(initialLocation: AppRoutes.authLanding, routes: [
        GoRoute(
            path: AppRoutes.authLanding,
            builder: (_, __) => const AuthLandingScreen()),
        GoRoute(
            path: AppRoutes.login,
            builder: (_, __) =>
                const Scaffold(body: Text('Email destination'))),
        GoRoute(
            path: AppRoutes.register,
            builder: (_, __) =>
                const Scaffold(body: Text('Register destination'))),
      ]);
      await pumpIntro(tester, router, brightness);
      expect(tester.takeException(), isNull);
      expect(find.text('Үнэгүй бүртгэл. Үнэгүй хэрэглээ.'), findsOneWidget);
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppColors.bgBase);
      await tester.ensureVisible(find.text('Имэйлээр нэвтрэх'));
      await tester.tap(find.text('Имэйлээр нэвтрэх'));
      await tester.pumpAndSettle();
      expect(find.text('Email destination'), findsOneWidget);
      router.go(AppRoutes.authLanding);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Шинээр бүртгүүлэх'));
      await tester.tap(find.text('Шинээр бүртгүүлэх'));
      await tester.pumpAndSettle();
      expect(find.text('Register destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('first run (Mongolian only)', () {
    late MockClient transport;
    setUp(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      // Supabase.initialize нь PKCE-д SharedPreferences ашигладаг; mock-ийг
      // эхлээд тавина (тест бүр өөрийн утгаар дахин тавина).
      SharedPreferences.setMockInitialValues({});
      // Session байхгүй — splash ямар ч сүлжээний хүсэлт илгээх ёсгүй.
      transport = MockClient((r) async =>
          throw StateError('Unexpected fixture request ${r.url}'));
      await Supabase.initialize(
        url: 'https://fixture.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        httpClient: transport,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            authFlowType: AuthFlowType.implicit,
            localStorage: EmptyLocalStorage()),
      );
    });
    tearDown(() async {
      await Supabase.instance.dispose();
      transport.close();
    });

    GoRouter splashRouter() =>
        GoRouter(initialLocation: AppRoutes.splash, routes: [
          GoRoute(
              path: AppRoutes.splash,
              builder: (_, __) => const SplashScreen()),
          GoRoute(
              path: AppRoutes.langSelect,
              builder: (_, __) =>
                  const Scaffold(body: Text('Language destination'))),
          GoRoute(
              path: AppRoutes.onboarding,
              builder: (_, state) => Scaffold(
                  body: Text(
                      'Onboarding ${state.uri.queryParameters['slide']}'))),
          GoRoute(
              path: AppRoutes.authLanding,
              builder: (_, __) =>
                  const Scaffold(body: Text('Auth destination'))),
        ]);

    testWidgets('new visitor skips language choice and stores Mongolian',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpIntro(tester, splashRouter(), Brightness.dark);
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Language destination'), findsNothing);
      expect(find.text('Onboarding 1'), findsOneWidget);
      expect(
          (await SharedPreferences.getInstance()).getString('locale'), 'mn');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('returning visitor with a stored English choice is moved to mn',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {'locale': 'en', 'onboarded': true});
      await pumpIntro(tester, splashRouter(), Brightness.light);
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Language destination'), findsNothing);
      expect(find.text('Auth destination'), findsOneWidget);
      expect(
          (await SharedPreferences.getInstance()).getString('locale'), 'mn');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('guest can open public places without creating an account',
      (tester) async {
    expect(AppRoutes.isPublic(AppRoutes.explore), isTrue);
    expect(AppRoutes.isPublic(AppRoutes.profile), isFalse);
    expect(AppRoutes.isPublic(AppRoutes.dmList), isFalse);
    final router = GoRouter(initialLocation: AppRoutes.authLanding, routes: [
      GoRoute(
          path: AppRoutes.authLanding,
          builder: (_, __) => const AuthLandingScreen()),
      GoRoute(
          path: AppRoutes.explore,
          builder: (_, __) => const Scaffold(body: Text('Public places'))),
    ]);
    await pumpIntro(tester, router, Brightness.light);
    final action = find.text('Бүртгэлгүйгээр газрууд үзэх');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Public places'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  GoRouter onboardingRouter(int slide) => GoRouter(
          initialLocation: '${AppRoutes.onboarding}?slide=$slide',
          routes: [
            GoRoute(
                path: AppRoutes.onboarding,
                builder: (_, state) => OnboardingScreen(
                    slide: int.tryParse(
                            state.uri.queryParameters['slide'] ?? '') ??
                        1)),
            GoRoute(
                path: AppRoutes.authLanding,
                builder: (_, __) =>
                    const Scaffold(body: Text('Auth destination'))),
            GoRoute(
                path: AppRoutes.permLocation,
                builder: (_, __) =>
                    const Scaffold(body: Text('Location destination'))),
          ]);

  testWidgets('intro explains actual features, optional location and finishes',
      (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'mn'});
    final router = onboardingRouter(1);
    await pumpIntro(tester, router, Brightness.dark);
    expect(find.text('Оройн газраа ол'), findsOneWidget);
    await tester.ensureVisible(find.text('Үргэлжлүүлэх'));
    await tester.tap(find.text('Үргэлжлүүлэх'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Мөчөө хамт хуваалц'), findsOneWidget);
    expect(find.text('Шууд дамжуулалт үз'), findsNothing);
    await tester.ensureVisible(find.text('Үргэлжлүүлэх'));
    await tester.tap(find.text('Үргэлжлүүлэх'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Байршлаа өөрөө сонго'), findsOneWidget);
    expect(find.textContaining('Зөвшөөрөлгүйгээр ч'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('ЭХЛЭХ'));
    await tester.tap(find.text('ЭХЛЭХ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
        (await SharedPreferences.getInstance()).getBool('onboarded'), isTrue);
    expect(find.text('Auth destination'), findsOneWidget);
  });

  testWidgets('intro skip remains optional and records completion',
      (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final router = onboardingRouter(2);
    await pumpIntro(tester, router, Brightness.light);
    expect(find.text('Share your moments'), findsOneWidget);
    expect(find.text('Watch Live Streams'), findsNothing);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Auth destination'), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance()).getBool('onboarded'), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final slide in [0, 999]) {
    testWidgets('out-of-range intro slide $slide stays usable', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'mn'});
      final router = onboardingRouter(slide);
      await pumpIntro(tester, router, Brightness.light);
      expect(find.text(slide == 0 ? 'Оройн газраа ол' : 'Байршлаа өөрөө сонго'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
        'reduced intro is immediately visible and has no pulse '
        '(accessibleNavigation=$accessibleNavigation)', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'mn'});
      final router = onboardingRouter(1);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: !accessibleNavigation,
                  accessibleNavigation: accessibleNavigation),
              child: child!)));
      await tester.pump();
      final entrances = tester.widgetList<FadeTransition>(find.descendant(
          of: find.byType(OnboardingScreen),
          matching: find.byType(FadeTransition)));
      expect(entrances, isNotEmpty);
      for (final entrance in entrances) {
        expect(entrance.opacity.value, 1);
        expect(entrance.opacity.status, AnimationStatus.completed);
      }
      final animated = tester.widgetList<AnimatedBuilder>(find.descendant(
          of: find.byType(OnboardingScreen),
          matching: find.byType(AnimatedBuilder)));
      final controllers = animated
          .map((widget) => widget.animation)
          .whereType<AnimationController>()
          .toList();
      expect(controllers, isNotEmpty);
      expect(
          controllers.every((controller) => !controller.isAnimating), isTrue);
      router.go('${AppRoutes.onboarding}?slide=2');
      await tester.pump();
      expect(find.text('Мөчөө хамт хуваалц'), findsOneWidget);
      for (final entrance in tester.widgetList<FadeTransition>(find.descendant(
          of: find.byType(OnboardingScreen),
          matching: find.byType(FadeTransition)))) {
        expect(entrance.opacity.value, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
