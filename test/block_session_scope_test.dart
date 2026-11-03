import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_owl_ub/core/theme/app_fonts.dart';
import 'package:night_owl_ub/features/post/services/content_publication.dart';
import 'package:night_owl_ub/features/profile/services/block_report_service.dart';
import 'package:night_owl_ub/features/profile/widgets/block_report_sheet.dart';

const _owner = '10000000-0000-0000-0000-000000000001';
const _target = '10000000-0000-0000-0000-000000000002';

class _Scope extends PublicationSession {
  bool active = true;
  @override
  String get ownerId => _owner;
  @override
  String get token => 'original-token';
  @override
  bool get isCurrent => active;
  @override
  void close() => active = false;
}

class _Blocks extends BlockMutationService {
  final scope = _Scope();
  int calls = 0;
  Completer<void>? pending;
  @override
  PublicationSession captureSession() => scope;
  @override
  Future<void> setBlocked(PublicationSession session, String target,
      {required bool blocked}) async {
    session.check();
    calls++;
    await pending?.future;
    session.check();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppFonts.configure();

  test('static block helpers fail safely before the app client is initialized',
      () async {
    expect(await BlockReportService.block(_target), isA<String>());
    expect(await BlockReportService.unblock(_target), isA<String>());
  });

  group('signed-out static helpers', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
          url: 'https://fixture.test',
          anonKey: 'public-fixture-key',
          debug: false,
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false,
              detectSessionInUri: false,
              localStorage: EmptyLocalStorage()));
    });
    tearDownAll(() => Supabase.instance.dispose());
    test('block and unblock return login guidance without throwing', () async {
      expect(await BlockReportService.block(_target), 'Нэвтэрнэ үү');
      expect(await BlockReportService.unblock(_target), 'Нэвтэрнэ үү');
    });
  });

  group('account-pinned block transport', () {
    late SupabaseClient client;
    late _Scope scope;
    late BlockMutationService service;
    final requests = <http.Request>[];
    late Future<http.Response> Function(http.Request) response;
    setUp(() {
      requests.clear();
      client = SupabaseClient('https://fixture.test', 'public-fixture-key');
      scope = _Scope();
      response = (_) async => http.Response('', 204);
      service = BlockMutationService(
          client: client,
          httpClient: MockClient((r) {
            requests.add(r);
            return response(r);
          }));
      client.auth.headers['authorization'] = 'Bearer newer-account';
    });
    tearDown(() async => client.dispose());

    test('block and unblock pin token/owner and preserve idempotent policy',
        () async {
      await service.setBlocked(scope, _target, blocked: true);
      await service.setBlocked(scope, _target, blocked: false);
      expect(requests.first.method, 'POST');
      expect(jsonDecode(requests.first.body),
          {'blocker_id': _owner, 'blocked_id': _target});
      expect(requests.first.headers['prefer'], contains('ignore-duplicates'));
      expect(requests.last.method, 'DELETE');
      expect(requests.last.url.queryParameters,
          {'blocker_id': 'eq.$_owner', 'blocked_id': 'eq.$_target'});
      for (final request in requests) {
        expect(request.headers['authorization'], 'Bearer original-token');
      }
    });

    test('stale scope cannot send and a late success cannot affect new account',
        () async {
      scope.active = false;
      await expectLater(service.setBlocked(scope, _target, blocked: true),
          throwsA(isA<PublicationFailure>()));
      expect(requests, isEmpty);
      scope.active = true;
      final pending = Completer<http.Response>();
      response = (_) => pending.future;
      final assertion = expectLater(
          service.setBlocked(scope, _target, blocked: true),
          throwsA(isA<PublicationFailure>()));
      await Future<void>.delayed(Duration.zero);
      scope.active = false;
      pending.complete(http.Response('', 201));
      await assertion;
      expect(requests, hasLength(1));
    });

    test('server payload is never displayed as a raw block error', () async {
      response = (_) async => http.Response(
          '{"message":"private-token-and-query","code":"42501"}', 403);
      await expectLater(
          service.setBlocked(scope, _target, blocked: true),
          throwsA(isA<PublicationFailure>().having((e) => e.message,
              'safe error', isNot(contains('private-token')))));
    });
  });

  for (final postMenu in [false, true]) {
    testWidgets(
        'block confirmation stays bound to original account ($postMenu)',
        (tester) async {
      final service = _Blocks();
      var changed = 0;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            blockMutationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () => postMenu
                              ? showPostOptionsSheet(context,
                                  postId: _target,
                                  authorId: _target,
                                  authorUsername: 'target',
                                  onBlocked: () => changed++)
                              : showUserOptionsSheet(context,
                                  userId: _target,
                                  username: 'target',
                                  onBlocked: () => changed++),
                          child: const Text('Open')))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('@target-г блоклох'));
      await tester.pumpAndSettle();
      service.scope.active = false;
      await tester.tap(find.text('Блоклох'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      expect(changed, 0);
      expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
