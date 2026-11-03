import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/router/app_router.dart';
import 'package:night_owl_ub/core/services/supabase_service.dart'
    show passwordJustReset;
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/utils/validators.dart';
import 'package:night_owl_ub/features/auth/screens/forgot_password_screen.dart';
import 'package:night_owl_ub/features/auth/screens/reset_password_screen.dart';
import 'package:night_owl_ub/features/auth/services/account_credentials_service.dart';
import 'package:night_owl_ub/features/profile/screens/change_password_screen.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';

Map<String, dynamic> user(String id) => {
      'id': id,
      'aud': 'authenticated',
      'created_at': '2026-11-03T00:00:00Z',
      'user_metadata': {'fixture_owner': id},
    };

http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class ControlledCredentials extends AccountCredentialsService {
  final Future<bool> result;
  ControlledCredentials(this.result);
  @override
  Future<bool> updatePassword(String password, {required String ownerId}) =>
      result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late http.Client transport;
  late AccountCredentialsService service;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) updateReply;
  late Future<http.Response> Function(http.Request) recoveryReply;
  var account = owner;
  var serial = 0;

  Future<void> signIn(String id) async {
    account = id;
    await client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fictional-password');
  }

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    passwordJustReset = false;
    account = owner;
    serial = 0;
    requests = [];
    updateReply = (_) async => response(user(owner));
    recoveryReply = (_) async => response({});
    transport = MockClient((r) async {
      requests.add(r);
      switch (r.url.path) {
        case '/auth/v1/token':
        case '/auth/v1/verify':
          final payload = base64Url
              .encode(utf8.encode(jsonEncode({
                'sub': account,
                'serial': ++serial,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              })))
              .replaceAll('=', '');
          return response({
            'access_token': 'fixture.$payload.signature',
            'refresh_token': 'fixture-$serial',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': user(account),
          });
        case '/auth/v1/user':
          if (r.method == 'PUT') return updateReply(r);
          return response(user(account));
        case '/auth/v1/recover':
          return recoveryReply(r);
        case '/auth/v1/logout':
          return response({});
        default:
          throw StateError('Unexpected fixture endpoint ${r.url.path}');
      }
    });
    await Supabase.initialize(
      url: 'https://fixture.example.test',
      anonKey: 'fixture-public-key',
      debug: false,
      httpClient: transport,
      authOptions: FlutterAuthClientOptions(
          pkceAsyncStorage: MemoryPkceStorage(),
          autoRefreshToken: false,
          detectSessionInUri: false,
          authFlowType: AuthFlowType.implicit,
          localStorage: const EmptyLocalStorage()),
    );
    client = Supabase.instance.client;
    service = AccountCredentialsService(client: client, httpClient: transport);
    await signIn(owner);
    requests.clear();
  });

  tearDown(() async {
    await Supabase.instance.dispose();
    transport.close();
    AppColors.isDarkMode = true;
    passwordJustReset = false;
  });

  List<http.Request> updates() =>
      requests.where((r) => r.url.path == '/auth/v1/user').toList();
  List<http.Request> logouts() =>
      requests.where((r) => r.url.path == '/auth/v1/logout').toList();

  test(
      'password transport captures owner JWT, sends only password and preserves user',
      () async {
    final jwt = client.auth.currentSession!.accessToken;
    expect(await service.updatePassword('fixture-secret-123', ownerId: owner),
        isTrue);
    expect(updates(), hasLength(1));
    expect(updates().single.headers['Authorization'], 'Bearer $jwt');
    expect(
        jsonDecode(updates().single.body), {'password': 'fixture-secret-123'});
    expect(client.auth.currentUser!.userMetadata!['fixture_owner'], owner);
  });

  test('wrong-owner password update never sends a request', () async {
    expect(await service.updatePassword('fixture-secret-123', ownerId: other),
        isFalse);
    expect(updates(), isEmpty);
  });

  for (final reloginSameOwner in [false, true]) {
    test(
        'late password result cannot replace ${reloginSameOwner ? 'a fresh same-owner login' : 'another owner'}',
        () async {
      final sent = Completer<void>();
      final held = Completer<http.Response>();
      updateReply = (_) {
        sent.complete();
        return held.future;
      };
      final result =
          service.updatePassword('fixture-secret-123', ownerId: owner);
      await sent.future;
      await signIn(other);
      if (reloginSameOwner) await signIn(owner);
      final session = client.auth.currentSession;
      held.complete(response(user(owner)));
      expect(await result, isFalse);
      expect(identical(client.auth.currentSession, session), isTrue);
      expect(logouts(), isEmpty);
    });
  }

  for (final code in [
    'same_password',
    'weak_password',
    'reauthentication_needed'
  ]) {
    test('password error $code is sanitized and does not clear the session',
        () async {
      updateReply = (_) async => response(
          {'code': code, 'msg': 'private raw response fixture-secret-123'},
          422);
      try {
        await service.updatePassword('fixture-secret-123', ownerId: owner);
        fail('Must reject the server error');
      } on AccountCredentialsFailure catch (e) {
        expect(e.code, code);
        expect(e.message, isNot(contains('private raw')));
        expect(e.message, isNot(contains('fixture-secret')));
      }
      expect(client.auth.currentUser!.id, owner);
    });
  }

  test(
      'email validation accepts plus addresses and rejects whitespace/missing domain',
      () {
    expect(Validators.email('person+night@example.test'), isNull);
    for (final value in [
      'person@',
      'person @example.test',
      'person@example test',
      'person@@example.test'
    ]) {
      expect(Validators.email(value), isNotNull);
    }
  });

  Future<GoRouter> pump(WidgetTester tester, Widget screen,
      {bool day = false, double height = 720, double scale = 1}) async {
    tester.view.physicalSize = Size(320, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    AppColors.isDarkMode = !day;
    final router = GoRouter(initialLocation: '/screen', routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      GoRoute(
          path: AppRoutes.settings,
          builder: (_, __) =>
              const Scaffold(body: Text('settings destination'))),
      GoRoute(
          path: AppRoutes.login,
          builder: (_, __) => const Scaffold(body: Text('login destination'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: day ? AppTheme.light : AppTheme.dark,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return router;
  }

  Future<void> drain(WidgetTester tester) async {
    // Bounded frames avoid treating a focused field's cursor as app loading.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> fillPassword(WidgetTester tester,
      [String password = 'fixture-password-123']) async {
    await tester.enterText(
        find.byKey(const ValueKey('new-password')), password);
    await tester.enterText(
        find.byKey(const ValueKey('confirm-password')), password);
    await tester.ensureVisible(find.byKey(const ValueKey('save-password')));
  }

  testWidgets(
      'settings password uses the same minimum as registration and recovery',
      (tester) async {
    await pump(tester, ChangePasswordScreen(service: service));
    await fillPassword(tester, '123456');
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await tester.pump();
    expect(
        tester
            .state<FormFieldState<String>>(
                find.byKey(const ValueKey('new-password')))
            .errorText,
        'Хамгийн багадаа 8 тэмдэгт');
    expect(updates(), isEmpty);
  });

  testWidgets(
      'pending password submission is single-flight and succeeds from direct route',
      (tester) async {
    final held = Completer<http.Response>();
    updateReply = (_) => held.future;
    await pump(tester, ChangePasswordScreen(service: service));
    await fillPassword(tester);
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(updates(), hasLength(1));
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('new-password')))
            .enabled,
        isFalse);
    held.complete(response(user(owner)));
    await drain(tester);
    expect(find.text('settings destination'), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .toList()
            .toString());
    expect(logouts(), isEmpty);
  });

  for (final reset in [false, true]) {
    testWidgets(
        '${reset ? 'recovery' : 'settings'} discards secrets and ignores old results after account switch',
        (tester) async {
      final held = Completer<http.Response>();
      updateReply = (_) => held.future;
      await pump(
          tester,
          reset
              ? ResetPasswordScreen(service: service)
              : ChangePasswordScreen(service: service));
      await fillPassword(tester);
      await tester.tap(find.byKey(const ValueKey('save-password')));
      await tester.pump();
      await signIn(other);
      await tester.pump();
      expect(find.byKey(const ValueKey('new-password')), findsNothing);
      held.complete(response(user(owner)));
      await drain(tester);
      expect(client.auth.currentUser!.id, other);
      expect(logouts(), isEmpty);
      expect(find.text('login destination'), findsNothing);
      expect(find.text('settings destination'), findsNothing);
      expect(passwordJustReset, isFalse);
      expect(
          tester.testTextInput.log.where((call) =>
              call.method == 'TextInput.finishAutofillContext' &&
              call.arguments == true),
          isEmpty);
    });
  }

  testWidgets(
      'successful recovery clears only its session and returns to login',
      (tester) async {
    await pump(tester, ResetPasswordScreen(service: service));
    await fillPassword(tester);
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await drain(tester);
    expect(find.text('login destination'), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .toList()
            .toString());
    expect(client.auth.currentSession, isNull);
    expect(logouts(), hasLength(1));
    expect(passwordJustReset, isTrue);
    expect(
        tester.testTextInput.log.where((call) =>
            call.method == 'TextInput.finishAutofillContext' &&
            call.arguments == true),
        isNotEmpty);
  });

  testWidgets('recovery without a session explains expiry and sends no update',
      (tester) async {
    await tester.runAsync(() => client.auth.signOut());
    requests.clear();
    await pump(tester, ResetPasswordScreen(service: service));
    await fillPassword(tester);
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await drain(tester);
    expect(find.textContaining('Холбоосын хугацаа дууссан'), findsOneWidget);
    expect(updates(), isEmpty);
  });

  testWidgets(
      'recovery failure preserves entered password and a safe actionable error',
      (tester) async {
    updateReply = (_) async => response(
        {'code': 'same_password', 'message': 'raw private detail'}, 422);
    await pump(tester, ResetPasswordScreen(service: service));
    await fillPassword(tester);
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await drain(tester);
    expect(find.textContaining('хуучин нууц үгээс өөр'), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .toList()
            .toString());
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('new-password')))
            .controller!
            .text,
        'fixture-password-123');
    expect(logouts(), isEmpty);
  });

  testWidgets(
      'forgot-password snapshots the address, guards repeats and uses native callback',
      (tester) async {
    final held = Completer<http.Response>();
    recoveryReply = (_) => held.future;
    await pump(tester, const ForgotPasswordScreen());
    await tester.enterText(find.byKey(const ValueKey('recovery-email')),
        ' person+night@example.test ');
    await tester.ensureVisible(find.byKey(const ValueKey('send-recovery')));
    await tester.tap(find.byKey(const ValueKey('send-recovery')));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final rows =
        requests.where((r) => r.url.path.endsWith('/recover')).toList();
    expect(rows, hasLength(1));
    expect(jsonDecode(rows.single.body)['email'], 'person+night@example.test');
    expect(rows.single.url.queryParameters['redirect_to'],
        'com.nightowl.ub://login-callback/');
    held.complete(response({}));
    await drain(tester);
    expect(find.textContaining('хаяг бүртгэлтэй бол'), findsOneWidget);
    expect(find.text('Имэйл хаягаа өөрчлөх'), findsOneWidget);
  });

  testWidgets(
      'a second recovery link replaces the old draft without applying its late result',
      (tester) async {
    final held = Completer<http.Response>();
    updateReply = (_) => held.future;
    await pump(tester, ResetPasswordScreen(service: service));
    await fillPassword(tester);
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await tester.pump();
    account = other;
    await tester.runAsync(() => client.auth
        .verifyOTP(tokenHash: 'fixture-recovery-hash', type: OtpType.recovery));
    await drain(tester);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('new-password')))
            .controller!
            .text,
        isEmpty);
    held.complete(response(user(owner)));
    await drain(tester);
    expect(client.auth.currentUser!.id, other);
    expect(
        find.textContaining('Шинэ сэргээх холбоос нээгдлээ'), findsOneWidget);
    expect(logouts(), isEmpty);
    updateReply = (_) async => response(user(other));
    await fillPassword(tester, 'other-fixture-password');
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await drain(tester);
    expect(find.text('login destination'), findsOneWidget);
    expect(logouts(), hasLength(1));
  });

  for (final reset in [false, true]) {
    testWidgets(
        '${reset ? 'recovery' : 'settings'} ignores a completed result during a fresh same-owner login',
        (tester) async {
      final completed = Completer<bool>();
      final controlled = ControlledCredentials(completed.future);
      await pump(
          tester,
          reset
              ? ResetPasswordScreen(service: controlled)
              : ChangePasswordScreen(service: controlled));
      await fillPassword(tester);
      await tester.tap(find.byKey(const ValueKey('save-password')));
      await tester.pump();
      await signIn(owner);
      await tester.pump();
      final fresh = client.auth.currentSession;
      completed.complete(true);
      await drain(tester);
      expect(identical(client.auth.currentSession, fresh), isTrue);
      expect(logouts(), isEmpty);
      expect(find.text('login destination'), findsNothing);
      expect(find.text('settings destination'), findsNothing);
      expect(passwordJustReset, isFalse);
    });
  }

  testWidgets(
      'disposing recovery before the response never signs out the owner',
      (tester) async {
    final held = Completer<http.Response>();
    updateReply = (_) => held.future;
    await pump(tester, ResetPasswordScreen(service: service));
    await fillPassword(tester);
    await tester.tap(find.byKey(const ValueKey('save-password')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    held.complete(response(user(owner)));
    await drain(tester);
    expect(client.auth.currentUser!.id, owner);
    expect(logouts(), isEmpty);
    expect(passwordJustReset, isFalse);
  });

  for (final day in [false, true]) {
    for (final kind in ['forgot', 'reset', 'change']) {
      testWidgets(
          '$kind fits a short 320px viewport with 1.5x text in ${day ? 'day' : 'night'}',
          (tester) async {
        final screen = switch (kind) {
          'forgot' => const ForgotPasswordScreen(),
          'reset' => ResetPasswordScreen(service: service),
          _ => ChangePasswordScreen(service: service),
        };
        await pump(tester, screen, day: day, height: 480, scale: 1.5);
        expect(tester.takeException(), isNull);
        final button = find.byKey(
            ValueKey(kind == 'forgot' ? 'send-recovery' : 'save-password'));
        await tester.ensureVisible(button);
        await tester.pump(const Duration(milliseconds: 200));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
