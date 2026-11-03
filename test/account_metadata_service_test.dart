import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/auth/services/account_metadata_service.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';

Map<String, dynamic> user(String id,
        [Map<String, dynamic> metadata = const {}]) =>
    {
      'id': id,
      'aud': 'authenticated',
      'created_at': '2026-11-03T00:00:00Z',
      'app_metadata': {'provider': 'email'},
      'user_metadata': metadata,
    };

http.Response reply(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'Content-Type': 'application/json'});

class RecordedStorage extends EmptyLocalStorage {
  String? saved;

  @override
  Future<void> persistSession(String persistSessionString) async {
    saved = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    saved = null;
  }
}

class TrackedClient extends MockClient {
  bool closed = false;
  TrackedClient(super.fn);

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late AccountMetadataService service;
  late TrackedClient transport;
  late RecordedStorage storage;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) updateReply;
  var account = owner;
  var tokenSerial = 0;

  Map<String, dynamic> session(String id) {
    final serial = ++tokenSerial;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': id,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'fixture_serial': serial,
        })))
        .replaceAll('=', '');
    return {
      'access_token': 'fixture.$payload.signature',
      'refresh_token': 'fixture-refresh-$serial',
      'token_type': 'bearer',
      'expires_in': 3600,
      'provider_token': 'fixture-provider-$serial',
      'provider_refresh_token': 'fixture-provider-refresh-$serial',
      'user': user(id),
    };
  }

  Future<void> signIn(String id) async {
    account = id;
    await client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-password');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    account = owner;
    tokenSerial = 0;
    requests = [];
    storage = RecordedStorage();
    updateReply = (_) async => reply(user(owner, {'setup_complete': true}));
    transport = TrackedClient((request) async {
      requests.add(request);
      expect(request.url.host, 'fixture.example.test');
      switch (request.url.path) {
        case '/auth/v1/token':
          return reply(session(account));
        case '/auth/v1/logout':
          return reply({});
        case '/auth/v1/user':
          if (request.method == 'PUT') return updateReply(request);
          return reply(user(account));
        default:
          throw StateError('Unexpected fixture endpoint');
      }
    });
    await Supabase.initialize(
      url: 'https://fixture.example.test',
      anonKey: 'fixture-public-key',
      debug: false,
      httpClient: transport,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        authFlowType: AuthFlowType.implicit,
        localStorage: storage,
      ),
    );
    client = Supabase.instance.client;
    service = AccountMetadataService(client: client, httpClient: transport);
    await signIn(owner);
    requests.clear();
  });

  tearDown(() async {
    await Supabase.instance.dispose();
    transport.close();
  });

  Future<({Future<bool> result, Completer<http.Response> response})>
      hold() async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    updateReply = (_) {
      sent.complete();
      return response.future;
    };
    final result = service.update({'setup_complete': true}, ownerId: owner);
    await sent.future;
    return (result: result, response: response);
  }

  test(
      'successful metadata update uses captured credentials and persists an event',
      () async {
    final before = client.auth.currentSession!;
    client.auth.headers['authorization'] = 'Bearer fixture-wrong-header';
    final events = <AuthState>[];
    final subscription = client.auth.onAuthStateChange.listen(events.add);
    addTearDown(subscription.cancel);
    expect(
        await service.update({'setup_complete': true}, ownerId: owner), isTrue);
    await Future<void>.delayed(Duration.zero);
    final request = requests.single;
    expect(request.method, 'PUT');
    expect(request.url.toString(), 'https://fixture.example.test/auth/v1/user');
    expect(request.headers['authorization'], 'Bearer ${before.accessToken}');
    expect(request.headers['apikey'], 'fixture-public-key');
    expect(jsonDecode(request.body), {
      'data': {'setup_complete': true}
    });
    final after = client.auth.currentSession!;
    expect(after.user.id, owner);
    expect(after.user.userMetadata?['setup_complete'], isTrue);
    expect(after.accessToken, before.accessToken);
    expect(after.refreshToken, before.refreshToken);
    expect(after.providerToken, before.providerToken);
    expect(after.providerRefreshToken, before.providerRefreshToken);
    expect(events.last.event, AuthChangeEvent.initialSession);
    expect(events.last.session?.user.userMetadata?['setup_complete'], isTrue);
    expect(
        jsonDecode(storage.saved!)['user']['user_metadata']['setup_complete'],
        isTrue);
    expect(transport.closed, isFalse,
        reason: 'The injected shared client stays usable.');
  });

  test('an A response cannot copy A user onto a newer B session', () async {
    final pending = await hold();
    await signIn(other);
    final latest = client.auth.currentSession!;
    pending.response.complete(reply(user(owner, {'setup_complete': true})));
    expect(await pending.result, isFalse);
    expect(client.auth.currentSession, same(latest));
    expect(client.auth.currentUser!.id, other);
    expect(jsonDecode(storage.saved!)['user']['id'], other);
  });

  test('a late response cannot recreate a signed out session', () async {
    final pending = await hold();
    await client.auth.signOut();
    pending.response.complete(reply(user(owner, {'setup_complete': true})));
    expect(await pending.result, isFalse);
    expect(client.auth.currentSession, isNull);
    expect(storage.saved, isNull);
  });

  test('signing back in as A still invalidates the original A request',
      () async {
    final pending = await hold();
    await signIn(owner);
    final latest = client.auth.currentSession!;
    pending.response.complete(reply(user(owner, {'setup_complete': true})));
    expect(await pending.result, isFalse);
    expect(client.auth.currentSession, same(latest));
    expect(client.auth.currentUser!.userMetadata, isEmpty);
  });

  test(
      'a same-owner refresh preserves all latest tokens while applying metadata',
      () async {
    final initial = client.auth.currentSession!;
    final pending = await hold();
    await client.auth.refreshSession();
    final refreshed = client.auth.currentSession!;
    expect(refreshed.accessToken, isNot(initial.accessToken));
    pending.response.complete(reply(user(owner, {'setup_complete': true})));
    expect(await pending.result, isTrue);
    final after = client.auth.currentSession!;
    expect(after.accessToken, refreshed.accessToken);
    expect(after.refreshToken, refreshed.refreshToken);
    expect(after.providerToken, refreshed.providerToken);
    expect(after.providerRefreshToken, refreshed.providerRefreshToken);
    expect(after.user.userMetadata?['setup_complete'], isTrue);
  });

  test('password recovery invalidates in-flight metadata', () async {
    final pending = await hold();
    final current = client.auth.currentSession!;
    await client.auth.getSessionFromUrl(Uri(
        scheme: 'com.nightowl.ub',
        host: 'login-callback',
        fragment: Uri(queryParameters: {
          'access_token': current.accessToken,
          'refresh_token': current.refreshToken!,
          'expires_in': '3600',
          'token_type': 'bearer',
          'type': 'recovery',
        }).query));
    final recovery = client.auth.currentSession!;
    pending.response.complete(reply(user(owner, {'setup_complete': true})));
    expect(await pending.result, isFalse);
    expect(client.auth.currentSession, same(recovery));
  });

  test('a concurrent user update invalidates in-flight metadata', () async {
    final pending = await hold();
    await client.auth.linkIdentityWithIdToken(
        provider: OAuthProvider.apple, idToken: 'fixture-identity-token');
    final latest = client.auth.currentSession!;
    pending.response.complete(reply(user(owner, {'setup_complete': true})));
    expect(await pending.result, isFalse);
    expect(client.auth.currentSession, same(latest));
  });

  test('wrong owner or signed out start sends no request', () async {
    expect(await service.update({'setup_complete': true}, ownerId: other),
        isFalse);
    expect(requests, isEmpty);
    await client.auth.signOut();
    requests.clear();
    expect(await service.update({'setup_complete': true}, ownerId: owner),
        isFalse);
    expect(requests, isEmpty);
  });

  for (final malformed in [
    user(other, {'setup_complete': true}),
    <String, dynamic>{
      'user_metadata': {'setup_complete': true}
    },
    <String, dynamic>{'id': owner, 'user_metadata': 'fixture-private-body'},
    <Object>[],
  ]) {
    test(
        'malformed or mismatched server user is rejected: ${malformed.runtimeType}',
        () async {
      final initial = client.auth.currentSession;
      updateReply = (_) async => reply(malformed);
      await expectLater(
          service.update({'setup_complete': true}, ownerId: owner),
          throwsA(isA<AccountMetadataFailure>()));
      expect(client.auth.currentSession, same(initial));
    });
  }

  for (final status in [401, 403, 429, 500]) {
    test('HTTP $status is sanitized and leaves local auth unchanged', () async {
      final initial = client.auth.currentSession;
      updateReply =
          (_) async => reply({'message': 'fixture-private-body'}, status);
      await expectLater(
          service.update({'setup_complete': true}, ownerId: owner),
          throwsA(isA<AccountMetadataFailure>().having(
              (error) => error.toString(),
              'message',
              isNot(contains('fixture-private')))));
      expect(client.auth.currentSession, same(initial));
    });
  }

  test('transport errors are sanitized and shared transport is not closed',
      () async {
    final initial = client.auth.currentSession;
    updateReply =
        (_) async => throw http.ClientException('fixture-private-token');
    await expectLater(
        service.update({'setup_complete': true}, ownerId: owner),
        throwsA(isA<AccountMetadataFailure>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('fixture-private')))));
    expect(client.auth.currentSession, same(initial));
    expect(transport.closed, isFalse);
  });

  test('timeout does not let a later HTTP response mutate auth', () async {
    service = AccountMetadataService(
        client: client,
        httpClient: transport,
        requestTimeout: const Duration(milliseconds: 10));
    final initial = client.auth.currentSession;
    final pending = await hold();
    await expectLater(pending.result, throwsA(isA<AccountMetadataFailure>()));
    pending.response.complete(reply(user(owner, {'setup_complete': true})));
    await Future<void>.delayed(Duration.zero);
    expect(client.auth.currentSession, same(initial));
  });

  test('an internally created HTTP transport is closed', () async {
    final owned = TrackedClient(
        (_) async => reply(user(owner, {'setup_complete': true})));
    expect(
        await http.runWithClient(
            () => AccountMetadataService(client: client)
                .update({'setup_complete': true}, ownerId: owner),
            () => owned),
        isTrue);
    expect(owned.closed, isTrue);
    expect(transport.closed, isFalse);
  });

  test('fixture confirms SDK updateUser would copy A user onto B session',
      () async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    updateReply = (_) {
      sent.complete();
      return response.future;
    };
    final unsafe =
        client.auth.updateUser(UserAttributes(data: {'setup_complete': true}));
    await sent.future;
    await signIn(other);
    final bToken = client.auth.currentSession!.accessToken;
    response.complete(reply(user(owner, {'setup_complete': true})));
    await unsafe;
    expect(client.auth.currentSession!.accessToken, bToken);
    expect(client.auth.currentUser!.id, owner,
        reason:
            'This isolated SDK regression is why production uses the guarded service.');
  });
}
