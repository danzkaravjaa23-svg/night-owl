import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/router/app_router.dart';
import 'package:night_owl_ub/core/utils/auth_return.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/profile/screens/delete_account_screen.dart';
import 'package:night_owl_ub/features/profile/services/account_deletion_service.dart';
import 'package:night_owl_ub/models/user_profile.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const privateError = 'fixture-private-internal-error';

http.Response jsonResponse(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'Content-Type': 'application/json'});

class FakeDeletionService extends AccountDeletionService {
  int requests = 0;
  int signOuts = 0;
  Completer<void>? pending;
  Object? failure;
  VoidCallback? onClear;

  @override
  Future<void> deleteOwnAccount(String expectedUserId) async {
    expect(expectedUserId, owner);
    requests++;
    await pending?.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<bool> clearDeletedSession(String expectedUserId) async {
    expect(expectedUserId, owner);
    signOuts++;
    onClear?.call();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'login can return to deletion but cannot target another origin or settings action',
      () {
    expect(AuthReturn.valid(AppRoutes.deleteAccount), AppRoutes.deleteAccount);
    expect(AuthReturn.valid('https://example.test/settings/delete-account'),
        isNull);
    expect(AuthReturn.valid(AppRoutes.changePassword), isNull);
  });

  group('Account deletion service with an isolated SDK HTTP double', () {
    late SupabaseClient client;
    late AccountDeletionService service;
    late List<http.Request> requests;
    late Future<http.Response> Function(http.Request) respond;
    late Future<http.Response> Function(http.Request) logoutReply;
    var account = owner;

    Future<void> signIn(String id) async {
      account = id;
      await client.auth.signInWithPassword(
          email: 'fixture@example.test', password: 'fixture-password');
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      requests = [];
      respond = (_) async => jsonResponse({'ok': true, 'user_id': owner});
      logoutReply = (_) async => jsonResponse({});
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
            if (request.url.path == '/auth/v1/token') {
              final payload = base64Url
                  .encode(utf8.encode(jsonEncode({
                    'sub': account,
                    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                  })))
                  .replaceAll('=', '');
              return jsonResponse({
                'access_token': 'fixture.$payload.fixture',
                'refresh_token': 'fixture-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': account,
                  'aud': 'authenticated',
                  'created_at': '2026-10-22T00:00:00Z'
                }
              });
            }
            if (request.url.path == '/auth/v1/logout') {
              return logoutReply(request);
            }
            expect(request.url.host, 'fixture.example.test');
            expect(request.url.path, '/functions/v1/delete-account');
            return respond(request);
          }));
      client = Supabase.instance.client;
      service = AccountDeletionService(client: client);
      await signIn(owner);
      requests.clear();
    });

    tearDown(() async => Supabase.instance.dispose());

    test(
        'pins caller authorization and explicit confirmation without a target user id',
        () async {
      final token = client.auth.currentSession!.accessToken;
      await service.deleteOwnAccount(owner);
      expect(requests, hasLength(1));
      expect(requests.single.method.toUpperCase(), 'POST');
      expect(requests.single.headers['Authorization'], 'Bearer $token');
      expect(jsonDecode(requests.single.body), {'confirmation': 'DELETE'});
      // The screen must verify its scope before clearing a session.
      expect(client.auth.currentUser?.id, owner);
      expect(await service.clearDeletedSession(owner), isTrue);
      expect(client.auth.currentUser, isNull);
      expect(requests.last.url.path, '/auth/v1/logout');
      expect(requests.last.url.queryParameters['scope'], 'local');
    });

    test(
        'a different owner cannot submit a request or clear the current session',
        () async {
      await expectLater(service.deleteOwnAccount(other),
          throwsA(isA<AccountDeletionFailure>()));
      expect(await service.clearDeletedSession(other), isFalse);
      expect(requests, isEmpty);
      expect(client.auth.currentUser?.id, owner);
    });

    test('a logged out caller cannot submit', () async {
      await client.auth.signOut();
      requests.clear();
      await expectLater(service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()));
      expect(requests, isEmpty);
    });

    for (final data in <Object>[
      {'ok': true},
      {'ok': 'true', 'user_id': owner},
      {'ok': true, 'user_id': other},
      [],
      'not a result'
    ]) {
      test('malformed or wrong-owner success does not clear a session: $data',
          () async {
        respond = (_) async => jsonResponse(data);
        await expectLater(service.deleteOwnAccount(owner),
            throwsA(isA<AccountDeletionFailure>()));
        expect(client.auth.currentUser?.id, owner);
        expect(requests.any((r) => r.url.path == '/auth/v1/logout'), isFalse);
      });
    }

    for (final entry in <(int, String)>[
      (503, 'deletion_unavailable'),
      (400, 'confirmation_required'),
      (409, 'apple_revocation_required'),
      (500, 'deletion_failed'),
      (500, 'deletion_incomplete'),
      (401, 'session_changed'),
      (404, 'deletion_unavailable')
    ]) {
      test('HTTP ${entry.$1} ${entry.$2} is localized, not a false success',
          () async {
        respond = (_) async =>
            jsonResponse({'code': entry.$2, 'error': privateError}, entry.$1);
        await expectLater(
            service.deleteOwnAccount(owner),
            throwsA(isA<AccountDeletionFailure>()
                .having((e) => e.code, 'code', entry.$2)
                .having((e) => e.message, 'message',
                    isNot(contains(privateError)))));
        expect(client.auth.currentUser?.id, owner);
      });
    }

    test('a transport error never promises that the operation was rolled back',
        () async {
      respond = (_) async => throw http.ClientException(privateError);
      await expectLater(
          service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>().having(
              (e) => e.message,
              'message',
              allOf(contains('устсан байж болно'),
                  isNot(contains(privateError))))));
      expect(client.auth.currentUser?.id, owner);
    });

    test('a late response cannot automatically log out a newer account',
        () async {
      final gate = Completer<http.Response>();
      respond = (_) => gate.future;
      final pending = service.deleteOwnAccount(owner);
      await signIn(other);
      gate.complete(jsonResponse({'ok': true, 'user_id': owner}));
      await pending;
      expect(await service.clearDeletedSession(owner), isFalse);
      expect(client.auth.currentUser?.id, other);
      expect(requests.any((r) => r.url.path == '/auth/v1/logout'), isFalse);
    });

    test('timeout is uncertain and does not log out or automatically retry',
        () async {
      final gate = Completer<http.Response>();
      service = AccountDeletionService(
          client: client, requestTimeout: const Duration(milliseconds: 250));
      respond = (_) => gate.future;
      final pending = service.deleteOwnAccount(owner);
      final failed = expectLater(
          pending,
          throwsA(isA<AccountDeletionFailure>()
              .having((e) => e.code, 'code', 'unknown')));
      await failed;
      gate.complete(jsonResponse({'ok': true, 'user_id': owner}));
      await Future<void>.delayed(Duration.zero);
      expect(client.auth.currentUser?.id, owner);
      expect(
          requests.where((r) => r.url.path == '/functions/v1/delete-account'),
          hasLength(1));
    });

    test(
        'stalled remote logout does not trap completed deletion or clear a later account',
        () async {
      final gate = Completer<http.Response>();
      logoutReply = (_) => gate.future;
      service = AccountDeletionService(
          client: client,
          sessionClearTimeout: const Duration(milliseconds: 50));
      expect(await service.clearDeletedSession(owner), isTrue);
      expect(client.auth.currentUser, isNull);
      await signIn(other);
      gate.complete(jsonResponse({}));
      await Future<void>.delayed(Duration.zero);
      expect(client.auth.currentUser?.id, other);
      expect(
          requests.where((r) => r.url.path == '/auth/v1/logout'), hasLength(1));
    });
  });

  group('Account deletion screen', () {
    late ProviderContainer container;
    late FakeDeletionService service;
    final session = StateProvider<String?>((ref) => owner);

    Future<void> render(WidgetTester tester, {String? user = owner}) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      service = FakeDeletionService();
      container = ProviderContainer(overrides: [
        session.overrideWith((ref) => user),
        sessionUserIdProvider.overrideWith((ref) => ref.watch(session)),
        currentProfileProvider.overrideWith(
            (ref) async => UserProfile(id: owner, username: 'fixture-person')),
        accountDeletionServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!),
              home: const DeleteAccountScreen())));
      await tester.pumpAndSettle();
    }

    Future<void> acknowledge(WidgetTester tester) async {
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-account-ack')), 150);
      await tester
          .ensureVisible(find.byKey(const ValueKey('delete-account-ack')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-account-ack')));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('delete-account-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-account-submit')));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await acknowledge(tester);
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    test(
        'completion route is accessible after logout without granting API access',
        () {
      expect(AppRoutes.isPublic(AppRoutes.deleteAccount), isTrue);
    });

    testWidgets(
        '320px large text requires acknowledgement and allows cancellation',
        (tester) async {
      await render(tester);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('delete-account-submit')), 150);
      await tester
          .ensureVisible(find.byKey(const ValueKey('delete-account-submit')));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('delete-account-submit')));
      expect(button.onPressed, isNull);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await acknowledge(tester);
      expect(service.requests, 0);
      await tester.tap(find.text('Цуцлах'));
      await tester.pumpAndSettle();
      expect(service.requests, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'confirmed success clears only the owner and keeps a completion message',
        (tester) async {
      await render(tester);
      service.onClear = () => container.read(session.notifier).state = null;
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(service.requests, 1);
      expect(service.signOuts, 1);
      expect(find.text('Бүртгэл устгагдлаа.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'unavailable service gives no success or logout and requires fresh confirmation',
        (tester) async {
      await render(tester);
      service.failure = const AccountDeletionFailure('deletion_unavailable');
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(service.requests, 1);
      expect(service.signOuts, 0);
      expect(find.text('Бүртгэл устгагдлаа.'), findsNothing);
      expect(find.textContaining('одоогоор бэлэн биш'), findsOneWidget);
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byKey(const ValueKey('delete-account-ack')))
              .value,
          isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'unknown failure is sanitized and warns about an uncertain outcome',
        (tester) async {
      await render(tester);
      service.failure = StateError(privateError);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining(privateError), findsNothing);
      expect(find.textContaining('устсан байж болно'), findsOneWidget);
      expect(service.signOuts, 0);
    });

    testWidgets(
        'switching account while the final dialog is open cannot submit',
        (tester) async {
      await render(tester);
      await acknowledge(tester);
      container.read(session.notifier).state = other;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pumpAndSettle();
      expect(service.requests, 0);
      expect(find.textContaining('Бүртгэл солигдлоо'), findsOneWidget);
    });

    for (final returnToOwner in [false, true]) {
      testWidgets(
          'late response after account switch ignores results (return=$returnToOwner)',
          (tester) async {
        await render(tester);
        service.pending = Completer<void>();
        await confirm(tester);
        expect(service.requests, 1);
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('delete-account-submit')), 150);
        await tester
            .ensureVisible(find.byKey(const ValueKey('delete-account-submit')));
        await tester.pump();
        expect(
            tester
                .widget<FilledButton>(
                    find.byKey(const ValueKey('delete-account-submit')))
                .onPressed,
            isNull);
        container.read(session.notifier).state = other;
        await tester.pump();
        if (returnToOwner) {
          container.read(session.notifier).state = owner;
          await tester.pump();
        }
        service.pending!.complete();
        await tester.pumpAndSettle();
        expect(service.signOuts, 0);
        expect(find.text('Бүртгэл устгагдлаа.'), findsNothing);
        expect(find.textContaining('Бүртгэл солигдлоо'), findsOneWidget);
      });
    }

    testWidgets(
        'a disposed screen does not log out an account on a late response',
        (tester) async {
      await render(tester);
      service.pending = Completer<void>();
      await confirm(tester);
      await tester.pumpWidget(const SizedBox());
      service.pending!.complete();
      await tester.pumpAndSettle();
      expect(service.signOuts, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a logged out visitor sees no destructive controls',
        (tester) async {
      await render(tester, user: null);
      expect(find.byKey(const ValueKey('delete-account-submit')), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(service.requests, 0);
    });
  });
}
