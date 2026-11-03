import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/shell/main_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<http.Request> heartbeats;
  Completer<http.Response>? pending;
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    heartbeats = [];
    pending = null;
    await Supabase.initialize(
        url: 'https://example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH' &&
              request.url.path == '/rest/v1/profiles') {
            heartbeats.add(request);
            if (pending != null) return pending!.future;
            return http.Response('', 204);
          }
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'});
        }));
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': 'fixture-owner',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        })))
        .replaceAll('=', '');
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'fixture.$payload.fixture',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'fixture-owner',
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z'
      },
    }));
  });
  tearDown(() => Supabase.instance.dispose());

  Future<void> render(WidgetTester tester, {double scale = 1}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final router = GoRouter(initialLocation: '/feed', routes: [
      ShellRoute(builder: (_, __, child) => MainShell(child: child), routes: [
        GoRoute(path: '/feed', builder: (_, __) => const Text('Feed fixture')),
        GoRoute(
            path: '/profile',
            builder: (_, __) => const Text('Profile fixture')),
      ]),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true, textScaler: TextScaler.linear(scale)),
          child: child!),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Navigation and create sheet fit narrow screens with doubled text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await render(tester, scale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Профайл'));
    await tester.pumpAndSettle();
    expect(find.text('Profile fixture'), findsOneWidget);
    await tester.tap(find.byTooltip('Шинээр үүсгэх'));
    await tester.pumpAndSettle();
    expect(find.text('Шинээр үүсгэх'), findsOneWidget);
    await tester.ensureVisible(find.text('Эвент'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('presence pauses in background and resumes only in foreground',
      (tester) async {
    await render(tester);
    expect(heartbeats, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    expect(heartbeats, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(heartbeats, hasLength(2));
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(heartbeats, hasLength(3));
    expect(
        heartbeats
            .every((r) => r.url.queryParameters['id'] == 'eq.fixture-owner'),
        isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(heartbeats, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow presence requests cannot pile up on timer ticks',
      (tester) async {
    pending = Completer<http.Response>();
    await render(tester);
    expect(heartbeats, hasLength(1));
    await tester.pump(const Duration(minutes: 3));
    expect(heartbeats, hasLength(1));
    pending!.complete(http.Response('', 204));
    pending = null;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(heartbeats, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
