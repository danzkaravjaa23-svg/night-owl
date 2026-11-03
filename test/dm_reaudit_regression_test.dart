import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/dm/screens/dm_thread_screen.dart';
import 'package:night_owl_ub/features/dm/widgets/notes_row.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';

const _me = '10000000-0000-0000-0000-000000000001';
const _nextAccount = '10000000-0000-0000-0000-000000000002';
const _peer = '10000000-0000-0000-0000-000000000003';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String account;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;

  http.Response json(http.Request request, Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: request, headers: {'content-type': 'application/json'});

  http.Response reply(http.Request request) {
    if (request.url.path.endsWith('/profiles')) {
      final id = request.url.queryParameters['id']!.substring(3);
      return json(request, {'id': id, 'username': 'fixture_peer'});
    }
    if (request.url.path.endsWith('/get_relationship')) {
      return json(request, {'dm_state': 'accepted', 'can_view': true});
    }
    if (request.url.path.endsWith('/messages') && request.method == 'GET') {
      return json(request, [
        {
          'id': '30000000-0000-0000-0000-000000000001',
          'sender_id': _peer,
          'receiver_id': account,
          'body': 'private history for $account',
          'created_at': '2026-10-20T00:00:00Z',
        }
      ]);
    }
    return json(request, null);
  }

  Future<void> signIn(String id) async {
    account = id;
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-password');
  }

  Future<ProviderContainer> render(
      WidgetTester tester, StateProvider<String> peer) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Consumer(builder: (context, ref, _) {
          return DmThreadScreen(
              threadId: ref.watch(peer), replyNote: 'private reply note');
        }))));
    await tester.pumpAndSettle();
    return container;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    account = _me;
    requests = [];
    respond = (r) async => reply(r);
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
            return json(request, {
              'access_token': 'fixture.$payload.fixture',
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': account,
                'aud': 'authenticated',
                'created_at': '2026-10-20T00:00:00Z'
              },
            });
          }
          return respond(request);
        }));
    await signIn(_me);
    requests.clear();
  });

  tearDown(() async => Supabase.instance.dispose());

  testWidgets(
      'failed send retains draft and does not overwrite a newer controller value',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? sending;
    respond = (r) async {
      if (r.url.path.endsWith('/send_direct_message')) {
        sending = r;
        return held.future;
      }
      return reply(r);
    };
    await render(tester, StateProvider<String>((ref) => _peer));
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'first message');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(sending, isNotNull);
    expect(tester.widget<TextField>(field).readOnly, isTrue);
    tester.widget<TextField>(field).controller!.text =
        'new unsent second draft';
    expect(tester.widget<TextField>(field).controller!.text,
        'new unsent second draft');
    held.complete(json(sending!, {'code': '42501', 'message': 'Denied'}, 403));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,
        'new unsent second draft');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual unread survives relationship polling', (tester) async {
    await render(tester, StateProvider<String>((ref) => _peer));
    await tester.tap(find.byTooltip('Бусад'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уншаагүй болгох'));
    await tester.pumpAndSettle();
    expect(
        requests
            .where(
                (r) => r.method == 'PATCH' && r.url.path.endsWith('/messages'))
            .any((r) => jsonDecode(r.body)['is_read'] == false),
        isTrue);
    requests.clear();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(
        requests
            .where(
                (r) => r.method == 'PATCH' && r.url.path.endsWith('/messages'))
            .any((r) => jsonDecode(r.body)['is_read'] == true),
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('covered thread cannot write read receipt', (tester) async {
    final held = Completer<http.Response>();
    http.Request? checking;
    int checks = 0;
    respond = (r) async {
      if (r.url.path.endsWith('/get_relationship') && ++checks == 2) {
        checking = r;
        return held.future;
      }
      return reply(r);
    };
    await render(tester, StateProvider<String>((ref) => _peer));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(checking, isNotNull);
    final context = tester.element(find.byType(DmThreadScreen));
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover route'))));
    await tester.pumpAndSettle();
    expect(find.text('Cover route'), findsOneWidget);
    requests.clear();
    held.complete(reply(checking!));
    await tester.pumpAndSettle();
    expect(
        requests
            .where(
                (r) => r.method == 'PATCH' && r.url.path.endsWith('/messages'))
            .any((r) => jsonDecode(r.body)['is_read'] == true),
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('note modal clears the old draft after account replacement',
      (tester) async {
    respond = (r) async {
      if (r.url.path.endsWith('/notes') && r.method == 'GET') {
        return json(r, []);
      }
      return reply(r);
    };
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Consumer(
                builder: (context, ref, _) => Scaffold(
                    body: NotesRow(
                        key: ValueKey(ref.watch(sessionUserIdProvider))))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note үлдээх...'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).first, 'private draft from first account');
    await signIn(_nextAccount);
    await tester.pumpAndSettle();
    expect(find.text('private draft from first account'), findsNothing);
    expect(find.text('Хуваалцах'), findsNothing);
    expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
    expect(
        requests
            .where((r) => r.method == 'POST' && r.url.path.endsWith('/notes')),
        isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
