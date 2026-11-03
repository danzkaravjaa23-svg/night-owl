import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/constants/community_rules.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/widgets/gradient_button.dart';
import 'package:night_owl_ub/core/widgets/policy_links.dart';
import 'package:night_owl_ub/features/auth/screens/auth_landing_screen.dart';
import 'package:night_owl_ub/features/auth/screens/login_screen.dart';
import 'package:night_owl_ub/features/auth/screens/register_screen.dart';
import 'package:night_owl_ub/features/auth/widgets/auth_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<http.Request> requests;
  Future<http.Response> Function(http.Request)? reply;
  Future<bool> Function(String)? launchReply;
  final opened = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  http.Response response(http.Request request, Object body,
          [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'});
  Map<String, Object> registeredUser() => {
        'id': 'fixture-registered-user',
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z',
      };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await Supabase.initialize(
        url: 'https://fixture.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (reply != null) return reply!(request);
          if (request.url.path.endsWith('/signup')) {
            return response(request, registeredUser());
          }
          return response(
              request, {'message': 'fixture invalid credentials'}, 400);
        }));
  });
  setUp(() {
    requests = [];
    reply = null;
    launchReply = null;
    opened.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'launch');
      final url = (call.arguments as Map)['url'] as String;
      opened.add(url);
      return launchReply?.call(url) ?? Future.value(true);
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AppColors.isDarkMode = true;
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> render(WidgetTester tester, String route,
      {Size size = const Size(390, 900),
      double scale = 1,
      bool dark = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    AppColors.isDarkMode = dark;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final router = GoRouter(initialLocation: route, routes: [
      GoRoute(path: '/auth', builder: (_, __) => const AuthLandingScreen()),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/auth/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/auth/setup',
          builder: (_, __) => const Scaffold(body: Text('Setup destination'))),
      GoRoute(
          path: '/explore',
          builder: (_, __) =>
              const Scaffold(body: Text('Explore destination'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: child!)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> fill(WidgetTester tester, {bool register = true}) async {
    final values = [
      if (register) 'Fixture Owl',
      'fixture@example.test',
      'fixture-password'
    ];
    for (var i = 0; i < values.length; i++) {
      final input = find.byType(TextFormField).at(i);
      await tester.ensureVisible(input);
      await tester.pumpAndSettle();
      await tester.enterText(input, values[i]);
      await tester.pump();
    }
  }

  Future<void> waitForRequest(WidgetTester tester) async {
    for (var i = 0; i < 20 && requests.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Finder submit() => find.byType(GradientButton).first;
  Finder google() => find.text('Google-ээр үргэлжлүүлэх');
  Finder agreement() =>
      find.byKey(const ValueKey('register-community-agreement'));

  testWidgets(
      'registration requires explicit 18+ agreement and sends complete metadata once',
      (tester) async {
    await render(tester, '/auth/register');
    await fill(tester);
    await tap(tester, submit());
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.text('18+ нас болон үйлчилгээний нөхцөлийг баталгаажуулна уу'),
        findsOneWidget);
    await tap(tester, agreement());
    final pending = Completer<http.Response>();
    http.Request? held;
    reply = (request) {
      held = request;
      return pending.future;
    };
    final before = DateTime.now().toUtc();
    await tap(tester, submit());
    final password = tester.widget<TextField>(find.descendant(
        of: find.byType(TextFormField).last, matching: find.byType(TextField)));
    password.onSubmitted?.call('fixture-password');
    await tester.pump();
    await waitForRequest(tester);
    expect(requests, hasLength(1));
    expect(held!.url.path, '/auth/v1/signup');
    final body = jsonDecode(held!.body) as Map;
    expect(body['email'], 'fixture@example.test');
    final metadata = body['data'] as Map<String, dynamic>;
    expect(metadata['full_name'], 'Fixture Owl');
    expect(CommunityRules.isAccepted(metadata), isTrue);
    final accepted =
        DateTime.parse(metadata['community_rules_accepted_at'] as String);
    expect(accepted.isUtc, isTrue);
    expect(accepted.isBefore(before), isFalse);
    expect(
        tester
            .widget<AppleSignInButton>(find.byType(AppleSignInButton))
            .enabled,
        isFalse);
    expect(tester.widget<GradientButton>(submit()).onPressed, isNull);
    pending.complete(response(held!, registeredUser()));
    await tester.pumpAndSettle();
    expect(find.text('И-мэйлээ шалгаарай'), findsOneWidget);
    expect(find.text('Setup destination'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final route in ['/auth/login', '/auth/register']) {
    testWidgets(
        '$route blocks Apple and Google during an email request and recovers',
        (tester) async {
      await render(tester, route);
      await fill(tester, register: route.endsWith('register'));
      if (route.endsWith('register')) await tap(tester, agreement());
      final pending = Completer<http.Response>();
      http.Request? held;
      reply = (request) {
        held = request;
        return pending.future;
      };
      await tap(tester, submit());
      expect(
          tester
              .widget<AppleSignInButton>(find.byType(AppleSignInButton))
              .enabled,
          isFalse);
      expect(tester.widget<GradientButton>(submit()).onPressed, isNull);
      final googleButton =
          find.ancestor(of: google(), matching: find.byType(TextButton)).first;
      expect(tester.widget<TextButton>(googleButton).onPressed, isNull);
      await waitForRequest(tester);
      expect(requests, hasLength(1));
      pending
          .complete(response(held!, {'message': 'invalid credentials'}, 400));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<AppleSignInButton>(find.byType(AppleSignInButton))
              .enabled,
          isTrue);
      expect(tester.widget<GradientButton>(submit()).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final route in ['/auth', '/auth/login', '/auth/register']) {
    testWidgets('$route disables email and Apple until Google launch completes',
        (tester) async {
      await render(tester, route);
      final pending = Completer<bool>();
      launchReply = (_) => pending.future;
      await tap(tester, google());
      for (var i = 0; i < 20 && opened.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(opened, hasLength(1));
      expect(Uri.parse(opened.single).queryParameters['provider'], 'google');
      expect(
          tester
              .widget<AppleSignInButton>(find.byType(AppleSignInButton))
              .enabled,
          isFalse);
      expect(tester.widget<GradientButton>(submit()).onPressed, isNull);
      expect(requests, isEmpty);
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<AppleSignInButton>(find.byType(AppleSignInButton))
              .enabled,
          isTrue);
      expect(tester.widget<GradientButton>(submit()).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$route coordinates the Apple busy callback with its other entry points',
        (tester) async {
      await render(tester, route);
      final apple =
          tester.widget<AppleSignInButton>(find.byType(AppleSignInButton));
      expect(apple.onBusyChanged, isNotNull);
      apple.onBusyChanged!(true);
      await tester.pump();
      expect(tester.widget<GradientButton>(submit()).onPressed, isNull);
      expect(
          tester
              .widget<AppleSignInButton>(find.byType(AppleSignInButton))
              .enabled,
          isFalse);
      if (route != '/auth') {
        final input = tester.widget<TextField>(find.descendant(
            of: find.byType(TextFormField).last,
            matching: find.byType(TextField)));
        input.onSubmitted?.call('fixture-password');
        await tester.pump();
        expect(requests, isEmpty);
      }
      apple.onBusyChanged!(false);
      await tester.pump();
      expect(tester.widget<GradientButton>(submit()).onPressed, isNotNull);
      expect(
          tester
              .widget<AppleSignInButton>(find.byType(AppleSignInButton))
              .enabled,
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Apple button respects external disable and reports a single pending operation',
      (tester) async {
    final pending = Completer<void>();
    final busy = <bool>[];
    var calls = 0;
    Widget screen(bool enabled) => MaterialApp(
        home: Scaffold(
            body: AppleSignInButton(
                enabled: enabled,
                onBusyChanged: busy.add,
                onSignIn: () {
                  calls++;
                  return pending.future;
                })));
    await tester.pumpWidget(screen(false));
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    await tester.pumpWidget(screen(true));
    await tester.tap(find.byType(OutlinedButton));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    expect(calls, 1);
    expect(busy, [true]);
    pending.complete();
    await tester.pumpAndSettle();
    expect(busy, [true, false]);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull);
  });

  for (final dark in [true, false]) {
    for (final route in ['/auth/login', '/auth/register']) {
      testWidgets(
          '$route fits 320x480 at 1.5x in ${dark ? 'night' : 'day'} with reachable controls',
          (tester) async {
        await render(tester, route,
            size: const Size(320, 480), scale: 1.5, dark: dark);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(AppleSignInButton));
        await tester.pumpAndSettle();
        expect(find.byType(AppleSignInButton).hitTestable(), findsOneWidget);
        if (route.endsWith('register')) {
          final heading = find.text('Night Owl-д нэгдээрэй');
          expect(tester.getRect(heading).left, greaterThanOrEqualTo(20));
          expect(tester.getRect(heading).right, lessThanOrEqualTo(300));
          expect(tester.widget<Text>(heading).textAlign, TextAlign.center);
          for (final policy in [AppPolicy.terms, AppPolicy.privacy]) {
            await tap(tester, find.text(policy.title));
            await tester.pumpAndSettle();
            expect(opened.last, policy.uri.toString());
          }
          final checkbox =
              find.descendant(of: agreement(), matching: find.byType(Checkbox));
          await tester.ensureVisible(checkbox);
          await tester.pumpAndSettle();
          expect(checkbox.hitTestable(), findsOneWidget);
          await tester.tap(checkbox);
          await tester.pump();
          expect(tester.widget<CheckboxListTile>(agreement()).value, isTrue);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
