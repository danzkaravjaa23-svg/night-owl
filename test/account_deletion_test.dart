import 'package:night_owl_ub/features/profile/services/account_deletion_receipt_store.dart';
import 'package:night_owl_ub/features/auth/services/apple_auth_service.dart';
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

class MemoryReceiptStore extends AccountDeletionReceiptStore {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('fixture');
    this.value = value;
  }
}

class FakeDeletionService extends AccountDeletionService {
  int requests = 0;
  int signOuts = 0;
  Completer<void>? pending;
  Object? failure;
  VoidCallback? onClear;
  String? receiptOwner;
  @override
  String? get pendingOwnerId => receiptOwner;
  @override
  bool hasPendingReceipt(String ownerId) => receiptOwner == ownerId;

  @override
  Future<void> restorePendingReceipts() async {}

  @override
  Future<void> deleteOwnAccount(String expectedUserId,
      {Future<AppleDeletionProof> Function(AppleDeletionChallenge)?
          appleReauthorize}) async {
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
    late http.Client transport;
    late MemoryReceiptStore receipts;
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
      receipts = MemoryReceiptStore();
      respond = (request) async => jsonResponse(
          jsonDecode(request.body)['action'] == 'prepare'
              ? {
                  'ok': true,
                  'user_id': owner,
                  'receipt_token': 'A' * 43,
                  'apple_required': false
                }
              : {'ok': true, 'user_id': owner});
      logoutReply = (_) async => jsonResponse({});
      transport = MockClient((request) async {
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
      });
      await Supabase.initialize(
          url: 'https://fixture.example.test',
          anonKey: 'fixture-public-key',
          debug: false,
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false,
              detectSessionInUri: false,
              localStorage: EmptyLocalStorage()),
          httpClient: transport);
      client = Supabase.instance.client;
      service = AccountDeletionService(
          client: client, httpClient: transport, receiptStore: receipts);
      await signIn(owner);
      requests.clear();
    });

    tearDown(() async => Supabase.instance.dispose());

    test(
        'pins caller authorization and explicit confirmation without a target user id',
        () async {
      final token = client.auth.currentSession!.accessToken;
      await service.deleteOwnAccount(owner);
      expect(requests, hasLength(2));
      expect(requests.every((r) => r.method.toUpperCase() == 'POST'), isTrue);
      expect(
          requests.every((r) => r.headers['authorization'] == 'Bearer $token'),
          isTrue);
      expect(jsonDecode(requests.first.body), {
        'confirmation': 'DELETE',
        'action': 'prepare',
        'client_platform': 'native'
      });
      expect(jsonDecode(requests.last.body), {
        'confirmation': 'DELETE',
        'action': 'delete',
        'receipt_token': 'A' * 43,
        'client_platform': 'native'
      });
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
      final pending = expectLater(
          service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()
              .having((e) => e.code, 'code', 'session_changed')));
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
          client: client,
          httpClient: transport,
          receiptStore: receipts,
          requestTimeout: const Duration(milliseconds: 250));
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
          httpClient: transport,
          receiptStore: receipts,
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

    test(
        'Apple proof is bound to server challenge without a Supabase identity switch',
        () async {
      final initial = client.auth.currentSession;
      respond = (request) async =>
          jsonResponse(jsonDecode(request.body)['action'] == 'prepare'
              ? {
                  'ok': true,
                  'user_id': owner,
                  'receipt_token': 'A' * 43,
                  'apple_required': true,
                  'nonce': 'B' * 43,
                  'client_id': 'com.nightowl.ub.nightOwlUb',
                  'redirect_uri': null
                }
              : {'ok': true, 'user_id': owner});
      service = AccountDeletionService(
          client: client,
          httpClient: transport,
          receiptStore: receipts,
          appleReauthorize: (challenge) async {
            expect(challenge.nonce, 'B' * 43);
            expect(challenge.clientId, 'com.nightowl.ub.nightOwlUb');
            expect(challenge.web, isFalse);
            expect(client.auth.currentSession, same(initial));
            return const AppleDeletionProof('fresh-code', 'identity-proof');
          });
      await service.deleteOwnAccount(owner);
      expect(jsonDecode(requests.last.body)['apple_code'], 'fresh-code');
      expect(jsonDecode(requests.last.body)['apple_identity_token'],
          'identity-proof');
      expect(client.auth.currentSession, same(initial));
      expect(requests.where((r) => r.url.path.contains('/auth/')), isEmpty);
    });

    test('Apple cancellation sends no destructive phase and preserves login',
        () async {
      final initial = client.auth.currentSession;
      respond = (_) async => jsonResponse({
            'ok': true,
            'user_id': owner,
            'receipt_token': 'A' * 43,
            'apple_required': true,
            'nonce': 'B' * 43,
            'client_id': 'com.nightowl.ub.nightOwlUb'
          });
      service = AccountDeletionService(
          client: client,
          httpClient: transport,
          receiptStore: receipts,
          appleReauthorize: (_) async =>
              throw const AppleDeletionAuthorizationFailure('apple_cancelled'));
      await expectLater(
          service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()
              .having((e) => e.code, 'code', 'apple_cancelled')));
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body)['action'], 'prepare');
      expect(client.auth.currentSession, same(initial));
    });

    test('account change during Apple authorization never reaches delete',
        () async {
      final proof = Completer<AppleDeletionProof>();
      respond = (_) async => jsonResponse({
            'ok': true,
            'user_id': owner,
            'receipt_token': 'A' * 43,
            'apple_required': true,
            'nonce': 'B' * 43,
            'client_id': 'com.nightowl.ub.nightOwlUb'
          });
      service = AccountDeletionService(
          client: client,
          httpClient: transport,
          receiptStore: receipts,
          appleReauthorize: (_) => proof.future);
      final pending = expectLater(
          service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()
              .having((e) => e.code, 'code', 'session_changed')));
      await Future<void>.delayed(Duration.zero);
      await signIn(other);
      proof.complete(const AppleDeletionProof('fresh-code', 'identity-proof'));
      await pending;
      expect(
          requests.where((r) =>
              r.url.path.contains('/functions/') &&
              jsonDecode(r.body)['action'] == 'delete'),
          isEmpty);
      expect(client.auth.currentUser?.id, other);
    });

    test(
        'uncertain deletion recovers by receipt after Auth is gone, without another delete',
        () async {
      final gate = Completer<http.Response>();
      respond = (request) async {
        final action = jsonDecode(request.body)['action'];
        if (action == 'prepare') {
          return jsonResponse({
            'ok': true,
            'user_id': owner,
            'receipt_token': 'A' * 43,
            'apple_required': false
          });
        }
        if (action == 'delete') return gate.future;
        expect(action, 'status');
        expect(request.headers['authorization'], 'Bearer fixture-public-key');
        return jsonResponse({'ok': true, 'user_id': owner});
      };
      service = AccountDeletionService(
          client: client,
          httpClient: transport,
          receiptStore: receipts,
          requestTimeout: const Duration(milliseconds: 50));
      await expectLater(service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()));
      await client.auth.signOut();
      // Restart: recover using only the encrypted durable status capability.
      service = AccountDeletionService(
          client: client, httpClient: transport, receiptStore: receipts);
      await service.deleteOwnAccount(owner);
      expect(await service.clearDeletedSession(owner), isTrue);
      final actions = requests
          .where((r) => r.url.path.contains('/functions/'))
          .map((r) => jsonDecode(r.body)['action']);
      expect(actions.toList(), ['prepare', 'delete', 'status']);
      gate.complete(jsonResponse({'ok': true, 'user_id': owner}));
      expect(client.auth.currentUser, isNull);
    });

    test('processing receipt is checked without starting a concurrent erase',
        () async {
      respond = (request) async => switch (jsonDecode(request.body)['action']) {
            'prepare' => jsonResponse({
                'ok': true,
                'user_id': owner,
                'receipt_token': 'A' * 43,
                'apple_required': false
              }),
            'delete' => jsonResponse({'code': 'deletion_incomplete'}, 500),
            _ => jsonResponse({
                'ok': false,
                'processing': true,
                'code': 'deletion_incomplete'
              }, 202),
          };
      await expectLater(service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()));
      await expectLater(
          service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()
              .having((e) => e.code, 'code', 'deletion_busy')));
      expect(requests.map((r) => jsonDecode(r.body)['action']).toList(),
          ['prepare', 'delete', 'status']);
    });

    test('completion cannot clear a new login for the same account', () async {
      await service.deleteOwnAccount(owner);
      await signIn(owner);
      requests.clear();
      expect(await service.clearDeletedSession(owner), isFalse);
      expect(client.auth.currentUser?.id, owner);
      expect(requests, isEmpty);
    });

    test(
        'a persisted foreign receipt cannot operate on a newly logged-in account',
        () async {
      receipts.value = jsonEncode([
        {
          'owner_id': owner,
          'receipt_token': 'A' * 43,
          'started_at': DateTime.now().toUtc().toIso8601String()
        }
      ]);
      await signIn(other);
      requests.clear();
      await expectLater(
          service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()
              .having((e) => e.code, 'code', 'session_changed')));
      expect(requests, isEmpty);
      expect(client.auth.currentUser?.id, other);
    });

    test('unavailable secure storage blocks the destructive phase', () async {
      receipts.fail = true;
      await expectLater(
          service.deleteOwnAccount(owner),
          throwsA(isA<AccountDeletionFailure>()
              .having((e) => e.code, 'code', 'receipt_storage_unavailable')));
      expect(requests.map((r) => jsonDecode(r.body)['action']).toList(),
          ['prepare']);
      expect(client.auth.currentUser?.id, owner);
    });

    test(
        'receipt validation ignores expired, future, malformed and proof-bearing records',
        () async {
      receipts.value = jsonEncode([
        {
          'owner_id': owner,
          'receipt_token': 'A' * 43,
          'started_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 31))
              .toIso8601String()
        },
        {
          'owner_id': owner,
          'receipt_token': 'B' * 43,
          'started_at': '2099-01-01T00:00:00Z'
        },
        {
          'owner_id': owner,
          'receipt_token': 'bad',
          'started_at': DateTime.now().toUtc().toIso8601String()
        },
        {
          'owner_id': owner,
          'receipt_token': 'C' * 43,
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'apple_identity_token': 'never-accept-persisted-proof'
        },
      ]);
      final original = receipts.value;
      await service.restorePendingReceipts();
      expect(service.pendingOwnerId, isNull);
      expect(service.hasPendingReceipt(owner), isFalse);
      expect(receipts.value, original);
      expect(requests, isEmpty);
    });

    test('completion removes only the matching owner receipt', () async {
      receipts.value = jsonEncode([
        for (final id in [owner, other])
          {
            'owner_id': id,
            'receipt_token': (id == owner ? 'A' : 'B') * 43,
            'started_at': DateTime.now().toUtc().toIso8601String()
          }
      ]);
      await service.deleteOwnAccount(owner);
      expect(jsonDecode(requests.single.body)['action'], 'status');
      expect(await service.clearDeletedSession(owner), isTrue);
      final saved = jsonDecode(receipts.value!) as List;
      expect(saved, hasLength(1));
      expect(saved.single['owner_id'], other);
    });
  });

  group('Account deletion screen', () {
    late ProviderContainer container;
    late FakeDeletionService service;
    final session = StateProvider<String?>((ref) => owner);

    Future<void> render(WidgetTester tester,
        {String? user = owner, bool recovering = false}) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      service = FakeDeletionService()..receiptOwner = recovering ? owner : null;
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
        'signed-out restart offers receipt status without destructive confirmation',
        (tester) async {
      await render(tester, user: null, recovering: true);
      expect(find.byKey(const ValueKey('delete-account-submit')), findsNothing);
      expect(find.byKey(const ValueKey('delete-account-ack')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('delete-account-recover')));
      await tester.pumpAndSettle();
      expect(service.requests, 1);
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
