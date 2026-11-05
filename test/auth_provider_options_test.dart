import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:night_owl_ub/features/auth/services/auth_provider_settings.dart';
import 'package:night_owl_ub/features/auth/widgets/auth_provider_options.dart';
import 'package:night_owl_ub/features/auth/widgets/auth_ui.dart';

http.Response settingsResponse({bool google = false, bool apple = false}) =>
    http.Response(
        jsonEncode({
          'external': {'google': google, 'apple': apple}
        }),
        200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('public settings carries no user token and preserves explicit flags',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/auth/v1/settings');
      expect(request.headers['apikey'], isNotEmpty);
      expect(request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')));
      return settingsResponse(apple: true);
    });
    addTearDown(client.close);
    final value = await AuthProviderSettings(client: client).fetch();
    expect(value.apple, isTrue);
    expect(value.google, isFalse);
  });

  test('shared requests and cache expire, while sign-in forces a fresh check',
      () async {
    var requests = 0;
    var now = DateTime.utc(2026, 11, 6);
    var enabled = true;
    final pending = Completer<http.Response>();
    final client = MockClient((_) async {
      requests++;
      return requests == 1
          ? await pending.future
          : settingsResponse(google: enabled);
    });
    addTearDown(client.close);
    final settings = AuthProviderSettings(client: client, now: () => now);
    final first = settings.fetch();
    final concurrent = settings.fetch();
    pending.complete(settingsResponse(google: true));
    expect((await first).google, isTrue);
    expect((await concurrent).google, isTrue);
    await settings.fetch();
    expect(requests, 1);
    enabled = false;
    await expectLater(
        settings.requireGoogle(), throwsA(isA<AuthProviderCheckFailure>()));
    expect(requests, 2);
    now = now.add(const Duration(minutes: 2));
    expect((await settings.fetch()).google, isFalse);
    expect(requests, 3);
  });

  for (final response in [
    http.Response('private malformed data', 200),
    http.Response('{"external":{"google":"true","apple":false}}', 200),
    http.Response('{"external":{"apple":true}}', 200),
    http.Response('private backend error', 503)
  ]) {
    test(
        'unknown or failing settings never enables a provider: ${response.body}',
        () async {
      final client = MockClient((_) async => response);
      addTearDown(client.close);
      await expectLater(
          AuthProviderSettings(client: client).fetch(),
          throwsA(isA<AuthProviderCheckFailure>().having(
              (error) => error.message,
              'safe message',
              isNot(contains('private')))));
    });
  }

  test('disabled Google stops before Supabase OAuth or an external launch',
      () async {
    // No Supabase instance is initialized in this suite. Reaching OAuth would
    // fail with a different exception, proving the guard runs first.
    final client = MockClient((_) async => settingsResponse());
    addTearDown(client.close);
    await expectLater(
        signInWithGoogle(settings: AuthProviderSettings(client: client)),
        throwsA(isA<AuthProviderCheckFailure>().having((error) => error.message,
            'disabled message', contains('идэвхгүй'))));
  });

  Future<void> render(WidgetTester tester, AuthProviderSettings settings,
      {VoidCallback? email, double textScale = 1}) async {
    await tester.pumpWidget(AuthProviderSettingsScope(
        settings: settings,
        child: MaterialApp(
            home: Scaffold(
                body: MediaQuery(
                    data: MediaQueryData(
                        textScaler: TextScaler.linear(textScale)),
                    child: SingleChildScrollView(
                        child: Column(children: [
                      TextButton(
                          onPressed: email ?? () {},
                          child: const Text('Email sign in')),
                      AuthProviderOptions(
                          showDivider: true,
                          googleButton: TextButton(
                              onPressed: () {}, child: const Text('Google')),
                          appleButton: TextButton(
                              onPressed: () {}, child: const Text('Apple'))),
                    ])))))));
    await tester.pump();
  }

  for (final flags in [
    (false, false),
    (true, false),
    (false, true),
    (true, true)
  ]) {
    testWidgets('only explicitly enabled provider buttons appear: $flags',
        (tester) async {
      final client = MockClient(
          (_) async => settingsResponse(google: flags.$1, apple: flags.$2));
      addTearDown(client.close);
      await render(tester, AuthProviderSettings(client: client));
      await tester.pumpAndSettle();
      expect(find.text('Google'), flags.$1 ? findsOneWidget : findsNothing);
      expect(find.text('Apple'), flags.$2 ? findsOneWidget : findsNothing);
      expect(find.byType(OrDivider),
          flags.$1 || flags.$2 ? findsOneWidget : findsNothing);
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Email sign in'))
              .onPressed,
          isNotNull);
    });
  }

  testWidgets(
      'checking and network failure keep email usable, with accessible retry',
      (tester) async {
    final pending = Completer<http.Response>();
    var requests = 0;
    var emails = 0;
    final client = MockClient((_) async => ++requests == 1
        ? await pending.future
        : settingsResponse(google: true));
    addTearDown(client.close);
    final semantics = tester.ensureSemantics();
    try {
      await render(tester, AuthProviderSettings(client: client),
          email: () => emails++, textScale: 2);
      expect(find.textContaining('шалгаж байна'), findsOneWidget);
      expect(find.text('Google'), findsNothing);
      expect(find.text('Apple'), findsNothing);
      await tester.tap(find.text('Email sign in'));
      expect(emails, 1);
      pending.completeError(http.ClientException('private transport details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('шалгаж чадсангүй'), findsOneWidget);
      expect(find.textContaining('private transport'), findsNothing);
      expect(find.bySemanticsLabel('Дахин шалгах'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-providers-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
      expect(requests, 2);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'late provider response after leaving auth does not update a disposed widget',
      (tester) async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    addTearDown(client.close);
    await render(tester, AuthProviderSettings(client: client));
    await tester.pumpWidget(const SizedBox());
    pending.complete(settingsResponse(apple: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
