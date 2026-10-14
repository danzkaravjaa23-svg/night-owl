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
import 'package:night_owl_ub/features/dm/screens/dm_list_screen.dart';

const _me = '00000000-0000-4000-8000-000000000001';
const _partner = '00000000-0000-4000-8000-000000000002';
const _group = '00000000-0000-4000-8000-000000000003';

Map<String, dynamic> _conversation(String body) => {
      'partner_id': _partner,
      'partner_username': 'fixture_friend',
      'partner_avatar_url': null,
      'partner_last_seen_at': null,
      'last_body': body,
      'last_at': '2026-10-05T00:00:00Z',
      'last_sender_id': _partner,
      'unread_count': 2,
    };

http.Response _reply(http.Request request, Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _pumpDm(WidgetTester tester,
    {Size size = const Size(390, 1000), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const DmListScreen()),
    GoRoute(
        path: '/search',
        builder: (_, __) =>
            const Scaffold(body: Text('Fixture people search'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(textScale)),
              child: child!))));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var failConversations = false;
  var hasGroup = false;
  var conversationRequests = 0;
  late List<Map<String, dynamic>> conversations;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    failConversations = false;
    hasGroup = false;
    conversationRequests = 0;
    conversations = [];
    await Supabase.initialize(
        url: 'https://fixture.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/auth/v1/token') {
            final payload = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': _me,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                })))
                .replaceAll('=', '');
            return _reply(request, {
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
          if (path == '/rest/v1/rpc/dm_conversations') {
            conversationRequests++;
            return failConversations
                ? _reply(request,
                    {'code': '42501', 'message': 'Fixture unavailable'}, 403)
                : _reply(request, conversations);
          }
          expect(request.method, 'GET',
              reason: 'Message state fixtures must never send or change data');
          if (path == '/rest/v1/group_members' && hasGroup) {
            return _reply(request, [
              {
                'group_id': _group,
                'group_chats': {
                  'id': _group,
                  'name': 'Fixture group',
                  'created_by': _me,
                  'created_at': '2026-10-05T00:00:00Z'
                },
              }
            ]);
          }
          if (path == '/rest/v1/group_messages') {
            return _reply(request, {
              'body': 'Fixture group message',
              'created_at': '2026-10-05T00:00:00Z'
            });
          }
          return _reply(request, []);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-password');
  });

  tearDown(() async => Supabase.instance.dispose());

  testWidgets('Initial failure has one error and retry, without a snackbar',
      (tester) async {
    failConversations = true;
    await _pumpDm(tester, size: const Size(320, 640), textScale: 1.5);
    expect(find.text('Ачаалж чадсангүй'), findsOneWidget);
    expect(find.text('Дахин оролдох'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(conversationRequests, 1);
    expect(tester.takeException(), isNull);

    failConversations = false;
    await tester.ensureVisible(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('Дахин оролдох').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(conversationRequests, 2);
    expect(find.text('Ачаалж чадсангүй'), findsNothing);
    expect(find.text('Мессеж алга байна'), findsOneWidget);
    expect(find.text('Хүн хайх'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Failed refresh retains conversations, groups and unread state',
      (tester) async {
    conversations = [_conversation('Previous conversation')];
    hasGroup = true;
    await _pumpDm(tester);
    expect(find.text('Previous conversation'), findsOneWidget);
    expect(find.text('Fixture group'), findsOneWidget);
    expect(find.text('1 шинэ'), findsOneWidget);

    failConversations = true;
    await tester.tap(find.byTooltip('Дахин ачаалах'));
    await tester.pumpAndSettle();
    expect(find.text('Previous conversation'), findsOneWidget);
    expect(find.text('Fixture group'), findsOneWidget);
    expect(find.text('1 шинэ'), findsOneWidget);
    expect(find.text('Шинэчилж чадсангүй'), findsOneWidget);
    expect(find.text('Дахин оролдох'), findsOneWidget);
    expect(find.text('Ачаалж чадсангүй'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    failConversations = false;
    conversations = [_conversation('Refreshed conversation')];
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('Refreshed conversation'), findsOneWidget);
    expect(find.text('Шинэчилж чадсангүй'), findsNothing);
    expect(conversationRequests, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Unmatched search can clear its query and restore conversations',
      (tester) async {
    conversations = [_conversation('Previous conversation')];
    await _pumpDm(tester);
    await tester.enterText(find.byType(TextField).first, 'unmatched query');
    await tester.pumpAndSettle();
    expect(find.text('Тохирох мессеж олдсонгүй'), findsOneWidget);
    expect(find.text('Мессеж алга байна'), findsNothing);
    await tester.ensureVisible(find.text('Хайлтыг цэвэрлэх'));
    await tester.pumpAndSettle();
    expect(find.text('Хайлтыг цэвэрлэх').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Хайлтыг цэвэрлэх'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        isEmpty);
    expect(find.text('Previous conversation'), findsOneWidget);
    expect(conversationRequests, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Empty conversations lead to the actual people-search route',
      (tester) async {
    await _pumpDm(tester);
    await tester.ensureVisible(find.text('Хүн хайх'));
    await tester.pumpAndSettle();
    expect(find.text('Хүн хайх').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Хүн хайх'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture people search'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
