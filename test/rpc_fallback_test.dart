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
import 'package:night_owl_ub/core/constants/app_constants.dart';
import 'package:night_owl_ub/core/services/legacy_rpc_fallback.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/features/dm/providers/group_provider.dart';
import 'package:night_owl_ub/features/dm/screens/dm_list_screen.dart';

const _me = '00000000-0000-4000-8000-000000000001';
const _partner = '00000000-0000-4000-8000-000000000002';
const _group = '00000000-0000-4000-8000-000000000003';
const _independent = AppConstants.backendMode == 'postgres';

Map<String, dynamic> _conversation() => {
      'partner_id': _partner,
      'partner_username': 'fixture_partner',
      'partner_avatar_url': null,
      'partner_last_seen_at': null,
      'last_body': 'Authorized RPC message',
      'last_at': '2026-10-05T00:00:00Z',
      'last_sender_id': _partner,
      'unread_count': 2,
    };

String _missingMessage(String rpc) => rpc == 'create_group'
    ? 'Could not find the function public.create_group(p_member_ids, p_name) in the schema cache'
    : 'Could not find the function public.dm_conversations without parameters in the schema cache';

http.Response _jsonResponse(http.Request request, Object? value,
        [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'}, request: request);

http.Response _errorResponse(http.Request request, String code, String message,
        [int status = 400]) =>
    _jsonResponse(request, {'code': code, 'message': message}, status);

Future<void> _pumpDm(WidgetTester tester) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const DmListScreen()),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Legacy fallback classification', () {
    bool permits(Object error,
            {String rpc = 'create_group',
            String mode = 'supabase',
            String url = 'https://fixture.supabase.co'}) =>
        canUseLegacyRpcFallback(error,
            rpcName: rpc, backendMode: mode, backendUrl: url);

    test('only the requested missing public RPC on managed HTTPS permits it',
        () {
      final missing = PostgrestException(
          message: _missingMessage('create_group'), code: 'PGRST202');
      expect(permits(missing), isTrue);
      expect(permits(missing, url: 'https://fixture.supabase.in'), isTrue);
      expect(permits(missing, mode: 'postgres'), isFalse);
      expect(
          permits(missing, mode: 'supabase', url: 'https://own.example.test'),
          isFalse);
      expect(permits(missing, url: 'http://fixture.supabase.co'), isFalse);
      expect(permits(missing, url: 'https://fixture.supabase.co.evil.test'),
          isFalse);
      expect(permits(missing, url: 'https://supabase.co'), isFalse);
      expect(
          permits(missing, url: 'https://user@fixture.supabase.co'), isFalse);
      expect(permits(missing, rpc: 'dm_conversations'), isFalse);
      expect(
          permits(const PostgrestException(
              message:
                  'Could not find the function private.create_group(p_name) in the schema cache',
              code: 'PGRST202')),
          isFalse);
      expect(
          permits(const PostgrestException(
              message:
                  'Could not find the function public.create_group_extra(p_name) in the schema cache',
              code: 'PGRST202')),
          isFalse);
      expect(
          permits(const PostgrestException(
              message:
                  'Could not find the public.create_group(p_member_ids, p_name) function in the schema cache',
              code: 'PGRST202')),
          isTrue);
    });

    test(
        'permissions, server validation, auth, transport and unrelated 404 deny it',
        () {
      for (final code in [
        '42501',
        '22023',
        'P0001',
        '42883',
        'PGRST301',
        'PGRST002',
        'PGRST203',
        'PGRST205',
        '404',
        null
      ]) {
        expect(
            permits(PostgrestException(
                message: _missingMessage('create_group'), code: code)),
            isFalse,
            reason: 'Only PGRST202 denotes the legacy unresolved RPC');
      }
      expect(
          permits(const PostgrestException(
              message: 'Active profile required', code: 'PGRST202')),
          isFalse);
      expect(permits(http.ClientException('fixture network failure')), isFalse);
      expect(permits(const FormatException('fixture malformed response')),
          isFalse);
    });
  });

  group('RPC HTTP boundaries', () {
    late List<http.Request> requests;
    late Future<http.Response> Function(http.Request) rpcReply;
    var rejectMembers = false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      GoogleFonts.config.allowRuntimeFetching = false;
      requests = [];
      rejectMembers = false;
      rpcReply = (request) async => _jsonResponse(request, []);
      await Supabase.initialize(
        url: AppConstants.backendUrl,
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path == '/auth/v1/token') {
            final payload = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': _me,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                })))
                .replaceAll('=', '');
            return _jsonResponse(request, {
              'access_token': 'fixture.$payload.fixture',
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': _me,
                'aud': 'authenticated',
                'created_at': '2026-10-05T00:00:00Z'
              },
            });
          }
          if (path.startsWith('/rest/v1/rpc/')) return rpcReply(request);
          if (path == '/rest/v1/group_chats' && request.method == 'POST') {
            return _jsonResponse(request, {'id': _group}, 201);
          }
          if (path == '/rest/v1/group_members' && request.method == 'POST') {
            if (rejectMembers) {
              return _errorResponse(request, '42501', 'Membership denied', 403);
            }
            return http.Response('', 201, request: request);
          }
          if (path == '/rest/v1/group_chats' && request.method == 'DELETE') {
            return http.Response('', 204, request: request);
          }
          if (path == '/rest/v1/messages') {
            return _jsonResponse(request, [
              {
                'sender_id': _me,
                'receiver_id': _partner,
                'body': 'Legacy direct message',
                'is_read': true,
                'created_at': '2026-10-05T00:00:00Z',
                'sender': {'id': _me, 'username': 'fixture_me'},
                'receiver': {'id': _partner, 'username': 'fixture_partner'},
              }
            ]);
          }
          return _jsonResponse(request, []);
        }),
      );
      await Supabase.instance.client.auth.signInWithPassword(
          email: 'fixture@example.test', password: 'fixture-password');
      requests.clear();
    });

    tearDown(() async {
      await Supabase.instance.dispose();
      AppColors.isDarkMode = true;
    });

    List<http.Request> directGroupWrites() => requests
        .where((r) =>
            !r.url.path.contains('/rpc/') &&
            {'POST', 'DELETE', 'PATCH'}.contains(r.method))
        .toList();
    List<http.Request> directMessages() =>
        requests.where((r) => r.url.path == '/rest/v1/messages').toList();

    test('valid group UUID returns without direct writes', () async {
      rpcReply = (request) async => _jsonResponse(request, _group);
      expect(await GroupService.createGroup('Fixture', [_partner, _partner]),
          _group);
      expect(directGroupWrites(), isEmpty);
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['p_member_ids'], [_partner, _me]);
    });

    test(
        '${_independent ? 'Independent' : 'Managed'} missing group RPC boundary',
        () async {
      rpcReply = (request) async => _errorResponse(
          request, 'PGRST202', _missingMessage('create_group'), 404);
      expect(await GroupService.createGroup('Fixture', [_partner]),
          _independent ? isNull : _group);
      expect(
          directGroupWrites().map((r) => r.url.path),
          _independent
              ? isEmpty
              : ['/rest/v1/group_chats', '/rest/v1/group_members']);
    });

    test('managed missing RPC still compensates a failed member insert',
        () async {
      rejectMembers = true;
      rpcReply = (request) async => _errorResponse(
          request, 'PGRST202', _missingMessage('create_group'), 404);
      expect(await GroupService.createGroup('Fixture', [_partner]), isNull);
      expect(
          directGroupWrites().map((r) => r.method), ['POST', 'POST', 'DELETE']);
      expect(directGroupWrites().last.url.queryParameters['id'], 'eq.$_group');
    }, skip: _independent);

    for (final code in ['42501', '22023', 'P0001', 'PGRST301', '42883']) {
      test('group $code rejection cannot become direct inserts', () async {
        rpcReply = (request) async =>
            _errorResponse(request, code, 'Fixture server rejection');
        expect(await GroupService.createGroup('Fixture', [_partner]), isNull);
        expect(directGroupWrites(), isEmpty);
      });
      testWidgets('DM $code rejection cannot become a direct messages query',
          (tester) async {
        rpcReply = (request) async =>
            _errorResponse(request, code, 'Fixture server rejection');
        await _pumpDm(tester);
        expect(directMessages(), isEmpty);
        expect(find.text('Ачаалж чадсангүй'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    test('group network failure cannot become direct inserts', () async {
      rpcReply = (_) async => throw http.ClientException('Fixture offline');
      expect(await GroupService.createGroup('Fixture', [_partner]), isNull);
      expect(directGroupWrites(), isEmpty);
    });
    testWidgets('DM network failure cannot become a direct messages query',
        (tester) async {
      rpcReply = (_) async => throw http.ClientException('Fixture offline');
      await _pumpDm(tester);
      expect(directMessages(), isEmpty);
      expect(find.text('Ачаалж чадсангүй'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    for (final result in <Object?>[
      null,
      '',
      'not-a-uuid',
      42,
      [],
      {'id': _group}
    ]) {
      test(
          'group malformed ${result.runtimeType} success cannot repeat transaction',
          () async {
        rpcReply = (request) async => _jsonResponse(request, result);
        expect(await GroupService.createGroup('Fixture', [_partner]), isNull);
        expect(directGroupWrites(), isEmpty);
      });
    }

    testWidgets(
        '${_independent ? 'Independent' : 'Managed'} missing DM RPC boundary',
        (tester) async {
      rpcReply = (request) async => _errorResponse(
          request, 'PGRST202', _missingMessage('dm_conversations'), 404);
      await _pumpDm(tester);
      expect(directMessages().length, _independent ? 0 : 1);
      expect(
          find.text(
              _independent ? 'Ачаалж чадсангүй' : 'Та: Legacy direct message'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    for (final empty in [false, true]) {
      testWidgets(
          'valid ${empty ? 'empty' : 'populated'} DM RPC never queries direct messages',
          (tester) async {
        rpcReply = (request) async =>
            _jsonResponse(request, empty ? [] : [_conversation()]);
        await _pumpDm(tester);
        expect(directMessages(), isEmpty);
        expect(
            find.text(empty ? 'Мессеж алга байна' : 'Authorized RPC message'),
            findsOneWidget);
        expect(find.text('Ачаалж чадсангүй'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    final malformed = <String, Object?>{
      'null': null,
      'object': {},
      'non-object row': ['invalid row'],
      'missing metadata': [{}],
      'missing last timestamp': [_conversation()..remove('last_at')],
      'null partner': [_conversation()..['partner_id'] = null],
      'invalid last timestamp': [_conversation()..['last_at'] = 'not-a-date'],
      'negative unread': [_conversation()..['unread_count'] = -1],
      'string unread': [_conversation()..['unread_count'] = '2'],
      'unrelated sender': [_conversation()..['last_sender_id'] = _group],
      'invalid body': [_conversation()..['last_body'] = 42],
      'duplicate partner': [_conversation(), _conversation()],
    };
    for (final entry in malformed.entries) {
      testWidgets('DM ${entry.key} success reports error without fallback',
          (tester) async {
        rpcReply = (request) async => _jsonResponse(request, entry.value);
        await _pumpDm(tester);
        expect(directMessages(), isEmpty);
        expect(find.text('Ачаалж чадсангүй'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
