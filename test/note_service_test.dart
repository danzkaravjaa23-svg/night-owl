import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/dm/services/note_service.dart';
import 'package:night_owl_ub/features/post/services/content_publication.dart';

void main() {
  const owner = '10000000-0000-4000-8000-000000000001';
  const other = '10000000-0000-4000-8000-000000000002';
  const venue = '20000000-0000-4000-8000-000000000001';
  late SupabaseClient client;
  late NoteService service;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  http.Response json(Object? value, [int status = 200]) =>
      http.Response(jsonEncode(value), status,
          headers: {'content-type': 'application/json'});

  Future<void> signIn(String id) async {
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': id,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        })))
        .replaceAll('=', '');
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'fixture.$payload.fixture',
      'refresh_token': 'refresh-$id',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': id,
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z',
      },
    }));
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    requests = [];
    final authTransport = MockClient((r) async =>
        throw StateError('Note must not use ambient Supabase transport'));
    client = SupabaseClient('https://notes-fixture.example.test', 'fixture-key',
        httpClient: authTransport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    respond = (r) async => json([
          {'user_id': owner, 'text': 'Saved note'}
        ]);
    final transport = MockClient((r) {
      requests.add(r);
      return respond(r);
    });
    addTearDown(transport.close);
    service = NoteService(client: client, transport: transport);
    await signIn(owner);
  });
  tearDown(() => client.dispose());

  test('upsert pins captured credentials, owner, text and 24 hour expiry',
      () async {
    final session = service.captureSession();
    addTearDown(session.close);
    final token = session.token;
    client.auth.headers.addAll({
      'authorization': 'Bearer wrong-token',
      'content-type': 'text/plain',
      'prefer': 'return=minimal',
    });
    await service.save(session, '  Saved note  ', venue);
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/notes');
    expect(request.url.queryParameters['on_conflict'], 'user_id');
    expect(request.url.queryParameters['select'],
        'user_id,text,moderation_status');
    expect(request.headers['authorization'], 'Bearer $token');
    expect(request.headers['apikey'], 'fixture-key');
    expect(request.headers['content-type'], 'application/json');
    expect(request.headers['prefer'],
        'resolution=merge-duplicates,return=representation');
    final row = jsonDecode(request.body) as Map;
    expect(row['user_id'], owner);
    expect(row['text'], 'Saved note');
    expect(row['venue_id'], venue);
    expect(
        DateTime.parse(row['expires_at'] as String)
            .difference(DateTime.parse(row['created_at'] as String)),
        const Duration(hours: 24));
  });

  for (final status in ['approved', 'pending', null]) {
    test('save returns the saved note review state $status', () async {
      respond = (r) async => json([
            {
              'user_id': owner,
              'text': 'Saved note',
              if (status != null) 'moderation_status': status
            }
          ]);
      final session = service.captureSession();
      addTearDown(session.close);
      expect(await service.save(session, 'Saved note', null), status);
    });
  }

  test('delete verifies the row returned for the captured owner', () async {
    final session = service.captureSession();
    addTearDown(session.close);
    await service.delete(session);
    final request = requests.single;
    expect(request.method, 'DELETE');
    expect(request.url.queryParameters['user_id'], 'eq.$owner');
    expect(request.headers['authorization'], 'Bearer ${session.token}');
    expect(request.headers['prefer'], 'return=representation');
  });

  for (final deleting in [false, true]) {
    Future<void> write(PublicationSession session) => deleting
        ? service.delete(session)
        : service.save(session, 'Saved note', null);

    test('stale note ${deleting ? 'delete' : 'save'} sends no request',
        () async {
      final session = service.captureSession();
      addTearDown(session.close);
      await signIn(other);
      await expectLater(write(session), throwsA(isA<PublicationFailure>()));
      expect(requests, isEmpty);
    });

    test(
        'same-account relogin invalidates note ${deleting ? 'delete' : 'save'} draft',
        () async {
      final session = service.captureSession();
      addTearDown(session.close);
      await signIn(owner);
      expect(client.auth.currentUser?.id, owner);
      await expectLater(write(session), throwsA(isA<PublicationFailure>()));
      expect(requests, isEmpty,
          reason: 'A new login must explicitly reopen the old draft');
    });

    test(
        'late note ${deleting ? 'delete' : 'save'} response rejects account switch',
        () async {
      final session = service.captureSession();
      addTearDown(session.close);
      final token = session.token;
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      final result =
          expectLater(write(session), throwsA(isA<PublicationFailure>()));
      await Future<void>.delayed(Duration.zero);
      await signIn(other);
      final newerSession = client.auth.currentSession;
      pending.complete(json([
        {'user_id': owner, 'text': 'Saved note'}
      ]));
      await result;
      expect(requests.single.headers['authorization'], 'Bearer $token');
      expect(client.auth.currentSession, same(newerSession));
    });

    test(
        'late note ${deleting ? 'delete' : 'save'} cannot confirm after same-account relogin',
        () async {
      final session = service.captureSession();
      addTearDown(session.close);
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      final result =
          expectLater(write(session), throwsA(isA<PublicationFailure>()));
      await Future<void>.delayed(Duration.zero);
      await signIn(owner);
      final newerSession = client.auth.currentSession;
      pending.complete(json([
        {'user_id': owner, 'text': 'Saved note'}
      ]));
      await result;
      expect(requests, hasLength(1));
      expect(client.auth.currentSession, same(newerSession));
    });

    test('zero-row note ${deleting ? 'delete' : 'save'} is not success',
        () async {
      final session = service.captureSession();
      addTearDown(session.close);
      respond = (_) async => json([]);
      await expectLater(write(session), throwsA(isA<PublicationFailure>()));
      expect(requests, hasLength(1));
    });
  }

  test('a response for another owner cannot confirm a note save', () async {
    final session = service.captureSession();
    addTearDown(session.close);
    respond = (_) async => json([
          {'user_id': other, 'text': 'Saved note'}
        ]);
    await expectLater(service.save(session, 'Saved note', null),
        throwsA(isA<PublicationFailure>()));
  });

  test('100 multi-codepoint emoji graphemes are accepted, 101 are rejected',
      () async {
    final session = service.captureSession();
    addTearDown(session.close);
    final text = '👨‍👩‍👧‍👦' * 100;
    expect(text.runes.length, greaterThan(100));
    respond = (_) async => json([
          {'user_id': owner, 'text': text}
        ]);
    await service.save(session, text, null);
    expect((jsonDecode(requests.single.body) as Map)['text'], text);
    await expectLater(service.save(session, '$text👨‍👩‍👧‍👦', null),
        throwsA(isA<PublicationFailure>()));
    expect(requests, hasLength(1));
  });
}
