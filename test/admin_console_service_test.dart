import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/admin/services/admin_console_service.dart';

const owner = '10000000-0000-4000-8000-000000000001';
const other = '10000000-0000-4000-8000-000000000002';
Matcher failure(String code) =>
    isA<AdminConsoleFailure>().having((e) => e.code, 'code', code);
http.Response jsonResponse(Object? value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'});
Map<String, dynamic> summary([String actor = owner]) => {
      'actor_id': actor,
      'users': 12,
      'posts': 4,
      'comments': 8,
      'venues': 3,
      'events': 2,
      'pending_reports': 1,
      'banned_users': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late AdminConsoleService service;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  Future<void> signIn(String id,
      {String label = 'initial', bool expired = false}) async {
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'fixture.${base64Url.encode(utf8.encode(jsonEncode({
                'sub': id,
                'label': label,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 +
                    (expired ? -3600 : 3600),
              }))).replaceAll('=', '')}.fixture',
      'refresh_token': 'refresh-$label',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': id,
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z'
      },
    }));
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    requests = [];
    respond = (_) async => jsonResponse(summary());
    client = SupabaseClient('https://admin-fixture.test', 'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      fail(
          'Ambient SDK transport must not be used for admin requests: ${request.url.path}');
    }));
    service = AdminConsoleService(
        client: client,
        requestTimeout: const Duration(milliseconds: 50),
        httpClient: MockClient((request) async {
          requests.add(request);
          return respond(request);
        }));
    await signIn(owner);
  });
  tearDown(() => client.dispose());
  AdminConsoleSession capture() {
    final session = service.captureSession();
    addTearDown(session.close);
    return session;
  }

  test('summary uses captured bearer, public API key and exact actor',
      () async {
    final session = capture();
    final result = await service.summary(session);
    expect(result.actorId, owner);
    expect(result.counts['users'], 12);
    expect(requests.single.url.path, '/rest/v1/rpc/admin_console_summary');
    expect(requests.single.headers['authorization'], 'Bearer ${session.token}');
    expect(requests.single.headers['apikey'], 'fixture-public');
    expect(jsonDecode(requests.single.body), isEmpty);
  });
  test('denied server role invalidates scope instead of returning zero counts',
      () async {
    respond = (_) async => jsonResponse({'code': '42501'}, 403);
    final session = capture();
    await expectLater(service.summary(session), throwsA(failure('denied')));
    expect(session.isCurrent, isFalse);
    await expectLater(service.records(session, kind: 'users'),
        throwsA(failure('session_changed')));
    expect(requests, hasLength(1));
  });
  test('missing migration is actionable and leaves same-account retry possible',
      () async {
    respond = (_) async => jsonResponse({'code': 'PGRST202'}, 404);
    final session = capture();
    await expectLater(
        service.summary(session), throwsA(failure('unavailable')));
    expect(session.isCurrent, isTrue);
    respond = (_) async => jsonResponse(summary());
    expect((await service.summary(session)).actorId, owner);
  });
  test('summary rejects a response authorized for a different actor', () async {
    respond = (_) async => jsonResponse(summary(other));
    final session = capture();
    await expectLater(service.summary(session), throwsA(failure('response')));
    expect(session.isCurrent, isFalse);
  });
  test('invalid reason sends no action and no direct table mutation', () async {
    final session = capture();
    for (final reason in ['', ' x ', 'ab']) {
      await expectLater(
          service.action(session,
              action: 'ban_user', targetId: other, reason: reason),
          throwsA(failure('reason')));
    }
    expect(requests, isEmpty);
  });
  test('moderation and linked report resolution are one atomic RPC', () async {
    respond = (_) async => jsonResponse({
          'audit_id': '90000000-0000-4000-8000-000000000001',
          'action': 'delete_post',
          'target_id': 'post-id',
          'target_type': 'post',
          'report_id': 'report-id',
          'report_status': 'resolved',
          'created_at': '2026-11-03T00:00:00Z',
        });
    await service.action(capture(),
        action: 'delete_post',
        targetId: 'post-id',
        reason: '  Давхар спам  ',
        reportId: 'report-id');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/rest/v1/rpc/admin_console_action');
    expect(jsonDecode(requests.single.body), {
      'p_action': 'delete_post',
      'p_target_id': 'post-id',
      'p_reason': 'Давхар спам',
      'p_report_id': 'report-id',
    });
  });
  for (final code in ['PT409', '40001']) {
    test('stale report action ($code) fails explicitly without success receipt',
        () async {
      respond = (_) async => jsonResponse({'code': code}, 409);
      await expectLater(
          service.action(capture(),
              action: 'resolve_report',
              targetId: 'report-id',
              reason: 'Шалгасан'),
          throwsA(failure('conflict')));
      expect(requests, hasLength(1),
          reason: 'Conflicts must not retry mutations.');
    });
  }
  test('denial revokes every captured route for the same account', () async {
    final dashboard = capture();
    final pushedReport = capture();
    await service.summary(dashboard);
    respond = (_) async => jsonResponse({'code': '42501'}, 403);
    await expectLater(service.records(pushedReport, kind: 'reports'),
        throwsA(failure('denied')));
    expect(pushedReport.isCurrent, isFalse);
    expect(dashboard.isCurrent, isFalse);
    await expectLater(
        service.summary(dashboard), throwsA(failure('session_changed')));
    expect(requests, hasLength(2));
  });
  for (final mismatch in const [
    {'report_status': 'pending'},
    {'report_id': null},
    {'target_type': 'comment'},
    {'audit_id': 'not-an-audit-id'},
    {'created_at': null},
  ]) {
    test('linked moderation rejects incomplete receipt $mismatch', () async {
      respond = (_) async => jsonResponse({
            'audit_id': '90000000-0000-4000-8000-000000000001',
            'action': 'delete_post',
            'target_id': 'post-id',
            'target_type': 'post',
            'report_id': 'report-id',
            'report_status': 'resolved',
            'created_at': '2026-11-03T00:00:00Z',
            ...mismatch,
          });
      await expectLater(
          service.action(capture(),
              action: 'delete_post',
              targetId: 'post-id',
              reason: 'Шалгасан',
              reportId: 'report-id'),
          throwsA(failure('action_uncertain')));
    });
  }
  test(
      'lost action response reports uncertain outcome rather than safe failure',
      () async {
    respond = (_) => Completer<http.Response>().future;
    await expectLater(
        service.action(capture(),
            action: 'ban_user', targetId: other, reason: 'Шалгасан'),
        throwsA(failure('action_uncertain')));
    expect(requests, hasLength(1));
  });
  for (final sameUser in [false, true]) {
    test(
        'late response is discarded after ${sameUser ? 'same-user relogin' : 'account change'}',
        () async {
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      final session = capture();
      final token = session.token;
      final result = service.summary(session);
      final assertion =
          expectLater(result, throwsA(failure('session_changed')));
      await Future<void>.delayed(Duration.zero);
      await signIn(sameUser ? owner : other, label: 'new-login');
      pending.complete(jsonResponse(summary()));
      await assertion;
      expect(requests.single.headers['authorization'], 'Bearer $token');
      expect(client.auth.currentUser!.id, sameUser ? owner : other);
      expect(client.auth.currentSession!.accessToken, isNot(token));
    });
  }
  test('expired captured token cannot trigger an ambient SDK refresh',
      () async {
    await signIn(owner, expired: true);
    respond = (_) async => jsonResponse({'code': 'PGRST301'}, 401);
    await expectLater(
        service.summary(capture()), throwsA(failure('authentication')));
    expect(requests.single.url.path, '/rest/v1/rpc/admin_console_summary');
    expect(client.auth.currentUser!.id, owner);
  });
  test('malformed page is an error, never a fake empty result', () async {
    respond = (_) async => jsonResponse({'items': [], 'has_more': 'false'});
    await expectLater(service.records(capture(), kind: 'reports'),
        throwsA(failure('response')));
  });
  test(
      'paging and literal searches are RPC parameters, not interpolated filters',
      () async {
    respond = (_) async => jsonResponse({
          'items': [
            {'id': 'user-id'}
          ],
          'has_more': true
        });
    final result = await service.records(capture(),
        kind: 'users', search: 'x,(name)%', offset: 30);
    expect(result.hasMore, isTrue);
    expect(jsonDecode(requests.single.body),
        {'p_offset': 30, 'p_limit': 30, 'p_search': 'x,(name)%'});
  });
  test('legacy admin RPCs retain captured scope for list and void responses',
      () async {
    respond = (_) async => jsonResponse([
          {'id': 'candidate'}
        ]);
    final session = capture();
    expect(
        await service.callRpc(session, 'search_pilot_candidates',
            {'p_kind': 'creator', 'p_query': ''}),
        isA<List>());
    respond = (_) async => jsonResponse(null);
    await service.callRpc(session, 'set_pilot_entry',
        {'p_kind': 'creator', 'p_id': other, 'p_enabled': true});
    expect(requests, hasLength(2));
  });
  Map<String, dynamic> reviewItem() => {
        'id': '30000000-0000-4000-8000-000000000001',
        'kind': 'post',
        'review_version': '40000000-0000-4000-8000-000000000001',
        'content': <String, dynamic>{'caption': 'Selected safe draft'},
        'status': 'pending',
      };
  Map<String, dynamic> reviewReceipt(Map<String, dynamic> item) => {
        'target_id': item['id'],
        'target_type': item['kind'],
        'review_version': item['review_version'],
        'status': 'approved',
        'audit_id': '50000000-0000-4000-8000-000000000001',
        'created_at': '2026-11-03T08:00:00Z',
      };
  test('review queue filters and pagination use captured RPC contract',
      () async {
    respond = (_) async => jsonResponse({
          'items': [reviewItem()],
          'has_more': true
        });
    final session = capture();
    final page = await service.reviewQueue(session, kind: 'post', offset: 20);
    expect(page.hasMore, isTrue);
    expect(page.items.single['content'], {'caption': 'Selected safe draft'});
    expect(requests.single.url.path, '/rest/v1/rpc/admin_console_review_queue');
    expect(requests.single.headers['authorization'], 'Bearer ${session.token}');
    expect(jsonDecode(requests.single.body), {
      'p_kind': 'post',
      'p_status': 'pending',
      'p_offset': 20,
      'p_limit': 20
    });
  });
  test(
      'review decisions bind the exact content version and require matching audit',
      () async {
    final item = reviewItem();
    respond = (_) async => jsonResponse(reviewReceipt(item));
    await service.review(capture(),
        item: item, decision: 'approved', reason: 'Reviewed all media');
    expect(requests.single.url.path, '/rest/v1/rpc/admin_console_review');
    expect(jsonDecode(requests.single.body), {
      'p_kind': 'post',
      'p_target_id': item['id'],
      'p_version': item['review_version'],
      'p_decision': 'approved',
      'p_reason': 'Reviewed all media'
    });
    respond = (_) async => jsonResponse(
        {...reviewReceipt(item), 'review_version': 'wrong-version'});
    await expectLater(
        service.review(capture(),
            item: item, decision: 'approved', reason: 'Reviewed all media'),
        throwsA(failure('action_uncertain')));
  });
  test(
      'review refuses malformed queue records and invalid decisions before mutation',
      () async {
    respond = (_) async => jsonResponse({
          'items': [
            {'id': 'x', 'kind': 'post'}
          ],
          'has_more': false
        });
    await expectLater(
        service.reviewQueue(capture()), throwsA(failure('response')));
    requests.clear();
    await expectLater(
        service.review(capture(),
            item: reviewItem(),
            decision: 'make_admin',
            reason: 'Invalid review'),
        throwsA(failure('invalid')));
    await expectLater(
        service.review(capture(),
            item: reviewItem(), decision: 'approved', reason: 'x'),
        throwsA(failure('invalid')));
    expect(requests, isEmpty);
  });
  test('a late review completion cannot become success after account switch',
      () async {
    final pending = Completer<http.Response>();
    respond = (_) => pending.future;
    final future = service.review(capture(),
        item: reviewItem(), decision: 'approved', reason: 'Reviewed all media');
    final assertion = expectLater(future, throwsA(failure('session_changed')));
    await Future<void>.delayed(Duration.zero);
    await signIn(other);
    pending.complete(jsonResponse(reviewReceipt(reviewItem())));
    await assertion;
  });
  test('review timeout is uncertain and server denial revokes the admin scope',
      () async {
    respond = (_) => Completer<http.Response>().future;
    await expectLater(
        service.review(capture(),
            item: reviewItem(),
            decision: 'approved',
            reason: 'Reviewed all media'),
        throwsA(failure('action_uncertain')));
    final session = capture();
    respond = (_) async => jsonResponse({'code': '42501'}, 403);
    await expectLater(service.reviewQueue(session), throwsA(failure('denied')));
    expect(session.isCurrent, isFalse);
  });
}
