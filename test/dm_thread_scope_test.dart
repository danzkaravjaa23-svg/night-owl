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

const _me = '10000000-0000-0000-0000-000000000001';
const _nextAccount = '10000000-0000-0000-0000-000000000002';
const _peer = '10000000-0000-0000-0000-000000000003';
const _nextPeer = '10000000-0000-0000-0000-000000000004';

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
      return json(request, {'id': id, 'username': 'peer-$id'});
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

  testWidgets('account changes clear private history and composer drafts',
      (tester) async {
    final peer = StateProvider<String>((ref) => _peer);
    await render(tester, peer);
    expect(find.text('private history for $_me'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first, 'private account draft');
    await signIn(_nextAccount);
    await tester.pumpAndSettle();
    expect(find.text('private history for $_me'), findsNothing);
    expect(find.text('private history for $_nextAccount'), findsOneWidget);
    expect(find.text('private reply note'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'sign-out removes history, draft and reply note and stops polling',
      (tester) async {
    await render(tester, StateProvider<String>((ref) => _peer));
    await tester.enterText(
        find.byType(TextField).first, 'private account draft');
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await tester.pumpAndSettle();
    expect(find.text('private history for $_me'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('private reply note'), findsNothing);
    final count = requests.length;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(requests, hasLength(count));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a reused thread route starts with its own partner and draft',
      (tester) async {
    final peer = StateProvider<String>((ref) => _peer);
    final container = await render(tester, peer);
    await tester.enterText(find.byType(TextField).first, 'draft for old peer');
    container.read(peer.notifier).state = _nextPeer;
    await tester.pumpAndSettle();
    expect(find.text('peer-$_peer'), findsNothing);
    expect(find.text('peer-$_nextPeer'), findsWidgets);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late message responses cannot restore another account history',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? oldRequest;
    respond = (r) async {
      if (r.url.path.endsWith('/messages') &&
          r.method == 'GET' &&
          account == _me) {
        oldRequest = r;
        return held.future;
      }
      return reply(r);
    };
    await render(tester, StateProvider<String>((ref) => _peer));
    expect(oldRequest, isNotNull);
    await signIn(_nextAccount);
    await tester.pumpAndSettle();
    held.complete(json(oldRequest!, [
      {
        'id': '30000000-0000-0000-0000-000000000002',
        'sender_id': _peer,
        'receiver_id': _me,
        'body': 'late private history',
        'created_at': '2026-10-20T00:00:00Z',
      }
    ]));
    await tester.pumpAndSettle();
    expect(find.text('late private history'), findsNothing);
    expect(find.text('private history for $_nextAccount'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late profile response cannot start old-peer permission requests',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? oldRequest;
    respond = (r) async {
      if (r.url.path.endsWith('/profiles') &&
          r.url.queryParameters['id'] == 'eq.$_peer') {
        oldRequest = r;
        return held.future;
      }
      return reply(r);
    };
    final peer = StateProvider<String>((ref) => _peer);
    final container = await render(tester, peer);
    container.read(peer.notifier).state = _nextPeer;
    await tester.pumpAndSettle();
    held.complete(reply(oldRequest!));
    await tester.pumpAndSettle();
    expect(find.text('peer-$_peer'), findsNothing);
    expect(
        requests.where((r) =>
            r.url.path.endsWith('/get_relationship') &&
            jsonDecode(r.body)['p_target'] == _peer),
        isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final change in ['thread', 'account']) {
    testWidgets('late failed send cannot put the old draft into a new $change',
        (tester) async {
      final held = Completer<http.Response>();
      http.Request? sendRequest;
      respond = (r) async {
        if (r.url.path.endsWith('/send_direct_message')) {
          sendRequest = r;
          return held.future;
        }
        return reply(r);
      };
      final peer = StateProvider<String>((ref) => _peer);
      final container = await render(tester, peer);
      await tester.enterText(find.byType(TextField).first, 'old private draft');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sendRequest, isNotNull);
      if (change == 'thread') {
        container.read(peer.notifier).state = _nextPeer;
      } else {
        await signIn(_nextAccount);
      }
      await tester.pumpAndSettle();
      held.complete(
          json(sendRequest!, {'code': '42501', 'message': 'Denied'}, 403));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('late permission response cannot authorize a different account',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? oldRequest;
    respond = (r) async {
      if (r.url.path.endsWith('/get_relationship')) {
        if (account == _me) {
          oldRequest = r;
          return held.future;
        }
        return json(r, {'dm_state': 'closed', 'can_view': false});
      }
      return reply(r);
    };
    await render(tester, StateProvider<String>((ref) => _peer));
    await signIn(_nextAccount);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'new account draft');
    held.complete(
        json(oldRequest!, {'dm_state': 'accepted', 'can_view': true}));
    await tester.pumpAndSettle();
    final send = find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.label == 'Мессеж илгээх');
    expect(tester.widget<Semantics>(send).properties.enabled, isFalse);
    expect(find.text('Нууцлалын тохиргоогоор мессеж хязгаарлагдсан'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('same-account session updates preserve the current draft',
      (tester) async {
    await render(tester, StateProvider<String>((ref) => _peer));
    await tester.enterText(find.byType(TextField).first, 'keep my draft');
    await signIn(_me);
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'keep my draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
