import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/services/supabase_service.dart';
import 'package:night_owl_ub/core/utils/auth_callback.dart';
import 'package:night_owl_ub/features/auth/services/apple_auth_service.dart';
import 'package:night_owl_ub/features/auth/widgets/auth_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Apple provider status', () {
    test(
        'an enabled provider is checked before login using the public settings endpoint',
        () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/auth/v1/settings');
        expect(request.headers['apikey'], isNotEmpty);
        expect(request.headers.keys.map((key) => key.toLowerCase()),
            isNot(contains('authorization')));
        return http.Response('{"external":{"apple":true}}', 200);
      });
      addTearDown(client.close);
      await requireAppleProvider(client: client);
    });

    test('a disabled provider gives an actionable local message', () async {
      final client = MockClient(
          (_) async => http.Response('{"external":{"apple":false}}', 200));
      addTearDown(client.close);
      await expectLater(
          requireAppleProvider(client: client),
          throwsA(isA<AppleSignInFailure>().having(
              (e) => e.message,
              'message',
              allOf(contains('идэвхгүй'), contains('Google'),
                  contains('имэйл')))));
    });

    for (final body in [
      '[]',
      '{"external":{}}',
      '{"external":{"apple":"true"}}'
    ]) {
      test('malformed settings cannot enable Apple login: $body', () async {
        final client = MockClient((_) async => http.Response(body, 200));
        addTearDown(client.close);
        await expectLater(
            requireAppleProvider(client: client),
            throwsA(isA<AppleSignInFailure>().having(
                (e) => e.message, 'message', contains('шалгаж чадсангүй'))));
      });
    }

    test('invalid JSON is reported locally instead of leaking a parser error',
        () async {
      final client = MockClient((_) async => http.Response('not JSON', 200));
      addTearDown(client.close);
      await expectLater(requireAppleProvider(client: client),
          throwsA(isA<AppleSignInFailure>()));
    });

    test('a non-200 provider response cannot navigate to Apple', () async {
      final client = MockClient(
          (_) async => http.Response('{"external":{"apple":true}}', 503));
      addTearDown(client.close);
      await expectLater(
          requireAppleProvider(client: client),
          throwsA(isA<AppleSignInFailure>().having(
              (e) => e.message, 'message', contains('шалгаж чадсангүй'))));
    });

    test('network failure provides a retry message', () async {
      final client = MockClient(
          (_) async => throw http.ClientException('test transport failure'));
      addTearDown(client.close);
      await expectLater(
          requireAppleProvider(client: client),
          throwsA(isA<AppleSignInFailure>().having(
              (e) => e.message, 'message', contains('Сүлжээгээ шалгаад'))));
    });
  });

  group('OAuth return URLs', () {
    test(
        'web redirects preserve the deployment subpath and remove login credentials',
        () {
      expect(
          oauthRedirectUrl(
              isWeb: true,
              baseUri: Uri.parse(
                  'https://app.example/night-owl/?code=temporary&campaign=invite#access_token=secret')),
          'https://app.example/night-owl/');
      expect(
          oauthRedirectUrl(
              isWeb: true, baseUri: Uri.parse('http://localhost:8765/#/auth')),
          'http://localhost:8765/');
      expect(
          oauthRedirectUrl(
              isWeb: true, baseUri: Uri.parse('https://app.example')),
          'https://app.example/');
    });

    test(
        'native redirects match the registered callback scheme regardless of launch URL',
        () {
      expect(
          oauthRedirectUrl(
              isWeb: false,
              baseUri: Uri.parse('https://app.example/night-owl/')),
          'com.nightowl.ub://login-callback/');
    });

    test(
        'consumed query credentials are removed while repeated non-auth parameters survive',
        () {
      final uri = Uri.parse(
          'https://app.example/night-owl/?code=temporary&state=nonce&error=access_denied'
          '&error_code=401&error_description=denied&access_token=token&refresh_token=refresh'
          '&provider_token=provider&provider_refresh_token=provider-refresh&expires_in=60'
          '&expires_at=999&token_type=bearer&token_hash=hash&type=signup&campaign=invite'
          '&tag=one&tag=two#access_token=fragment-token&refresh_token=fragment-refresh');
      final clean = cleanAuthCallbackUrl(uri);
      expect(clean.scheme, 'https');
      expect(clean.host, 'app.example');
      expect(clean.path, '/night-owl/');
      expect(clean.queryParametersAll, {
        'campaign': ['invite'],
        'tag': ['one', 'two']
      });
      expect(clean.fragment, '/auth');
      expect(hasOAuthCallback(clean), isFalse);
    });

    test(
        'fragment callbacks and native callbacks retain no credentials after cleaning',
        () {
      final web = cleanAuthCallbackUrl(Uri.parse(
          'http://localhost:8765/#access_token=secret&refresh_token=secret'));
      expect(web.toString(), 'http://localhost:8765/#/auth');
      final native = cleanAuthCallbackUrl(
          Uri.parse('com.nightowl.ub://login-callback/?code=temporary'));
      expect(native.scheme, 'com.nightowl.ub');
      expect(native.host, 'login-callback');
      expect(native.path, '/');
      expect(native.hasQuery, isFalse);
      expect(hasOAuthCallback(native), isFalse);
    });

    test('OAuth results are detected but ordinary routes and queries are not',
        () {
      for (final url in [
        'https://app.example/?code=one-use',
        'https://app.example/?error=access_denied',
        'https://app.example/#access_token=token',
        'https://app.example/#error_description=denied',
      ]) {
        expect(hasOAuthCallback(Uri.parse(url)), isTrue, reason: url);
      }
      for (final url in [
        'https://app.example/#/auth',
        'https://app.example/?campaign=invite#/feed'
      ]) {
        expect(hasOAuthCallback(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test(
        'callback errors distinguish cancellation, a disabled provider and an expired link',
        () {
      expect(
          oauthCallbackErrorMessage('access_denied'), contains('цуцлагдлаа'));
      expect(
          oauthCallbackErrorMessage('provider_disabled'), contains('идэвхгүй'));
      expect(oauthCallbackErrorMessage('unexpected'),
          contains('хугацаа нь дууссан'));
      expect(oauthCallbackErrorMessage(null),
          oauthCallbackErrorMessage('unexpected'));
    });
  });

  group('Native OAuth error stream', () {
    test(
        'SDK errors are sanitized once, auth events continue and late subscribers retain replay',
        () async {
      SharedPreferences.setMockInitialValues({});
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('[]', 200, request: request);
      });
      addTearDown(client.close);
      await Supabase.initialize(
        url: 'https://example.test',
        anonKey: 'test-only-anon-key',
        debug: false,
        httpClient: client,
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
      );
      authCallbackError.value = null;
      final subscriptions = <StreamSubscription<AuthState>>[];
      final errors = <Object>[];
      final messages = <String>[];
      final notice = Completer<void>();
      void observeNotice() {
        final message = authCallbackError.value;
        if (message == null) return;
        messages.add(message);
        // Match the app consuming/clearing a notice immediately. A second
        // stream listener must not re-show the same SDK error afterwards.
        authCallbackError.value = null;
        if (!notice.isCompleted) notice.complete();
      }

      authCallbackError.addListener(observeNotice);
      addTearDown(() async {
        authCallbackError.removeListener(observeNotice);
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await Supabase.instance.dispose();
        authCallbackError.value = null;
      });

      final signedOut = [Completer<void>(), Completer<void>()];
      for (final done in signedOut) {
        subscriptions.add(SupabaseService.authStream.listen((state) {
          if (state.event == AuthChangeEvent.signedOut && !done.isCompleted) {
            done.complete();
          }
        }, onError: (Object error) => errors.add(error)));
      }

      // Deliberately exercise the SDK pathway used by native deep links.
      // ignore: invalid_use_of_internal_member
      Supabase.instance.client.auth.notifyException(const AuthException(
        'RAW PAYLOAD: test-only token must never enter the UI',
        code: 'access_denied',
      ));
      await notice.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(messages, hasLength(1));
      expect(messages.single, contains('Нэвтрэлт цуцлагдлаа'));
      expect(messages.single, isNot(contains('RAW PAYLOAD')));
      expect(authCallbackError.value, isNull);
      expect(errors, isEmpty);

      // No user is signed in. The SDK emits this event locally and never
      // contacts a server or mutates any real account.
      await Supabase.instance.client.auth.signOut();
      await Future.wait(signedOut.map((done) => done.future))
          .timeout(const Duration(seconds: 2));
      final replay = Completer<AuthState>();
      subscriptions.add(SupabaseService.authStream.listen((state) {
        if (!replay.isCompleted) replay.complete(state);
      }, onError: (Object error) => errors.add(error)));
      expect((await replay.future.timeout(const Duration(seconds: 2))).event,
          AuthChangeEvent.signedOut);
      expect(errors, isEmpty);
      expect(messages, hasLength(1));
      expect(requests, 0);
    });
  });

  group('Apple login button', () {
    Widget screen(Future<void> Function() onSignIn) => MaterialApp(
        home: Scaffold(body: AppleSignInButton(onSignIn: onSignIn)));

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('Apple login is visible on $platform', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          var calls = 0;
          await tester.pumpWidget(screen(() async {
            calls++;
          }));
          expect(find.text('Apple-ээр үргэлжлүүлэх'), findsOneWidget);
          await tester.tap(find.byType(OutlinedButton));
          await tester.pumpAndSettle();
          expect(calls, 1);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets(
        'busy login prevents a rapid second tap and restores the button on completion',
        (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(screen(() {
        calls++;
        return pending.future;
      }));
      await tester.tap(find.byType(OutlinedButton));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Түр хүлээнэ үү…'), findsOneWidget);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Apple-ээр үргэлжлүүлэх'), findsOneWidget);
      expect(
          tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    });

    for (final knownFailure in [true, false]) {
      testWidgets(
          'a ${knownFailure ? 'provider' : 'generic'} failure stays local and permits retry',
          (tester) async {
        var calls = 0;
        await tester.pumpWidget(screen(() async {
          calls++;
          if (calls == 1) {
            if (knownFailure) {
              throw const AppleSignInFailure('Apple үйлчилгээ идэвхгүй байна');
            }
            throw StateError('internal test failure');
          }
        }));
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(
            find.text(knownFailure
                ? 'Apple үйлчилгээ идэвхгүй байна'
                : 'Apple-ээр нэвтрэхэд алдаа гарлаа. Дахин оролдоно уу.'),
            findsOneWidget);
        expect(find.text('internal test failure'), findsNothing);
        expect(
            tester
                .widget<OutlinedButton>(find.byType(OutlinedButton))
                .onPressed,
            isNotNull);
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(tester.takeException(), isNull);
      });
    }

    for (final fails in [false, true]) {
      testWidgets(
          'an in-flight ${fails ? 'failure' : 'success'} is safe after the button is disposed',
          (tester) async {
        final pending = Completer<void>();
        await tester.pumpWidget(screen(() => pending.future));
        await tester.tap(find.byType(OutlinedButton));
        await tester.pump();
        await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: Text('Another page'))));
        if (fails) {
          pending.completeError(const AppleSignInFailure('test late failure'));
        } else {
          pending.complete();
        }
        await tester.pumpAndSettle();
        expect(find.text('Another page'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
