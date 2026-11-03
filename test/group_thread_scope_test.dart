import 'dart:async';
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
import 'package:night_owl_ub/features/dm/screens/group_thread_screen.dart';

const _a = '10000000-0000-4000-8000-000000000001';
const _b = '10000000-0000-4000-8000-000000000002';
const _peer = '10000000-0000-4000-8000-000000000003';
const _group = '20000000-0000-4000-8000-000000000001';
const _other = '20000000-0000-4000-8000-000000000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String account;
  late int login;
  late List<http.Request> requests;
  Future<http.Response?> Function(http.Request)? intercept;

  http.Response json(http.Request r, Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: r, headers: {'content-type': 'application/json'});

  List<Map<String, dynamic>> messages(String text) => [
        {
          'id': '30000000-0000-4000-8000-000000000001',
          'group_id': _group,
          'sender_id': _peer,
          'body': text,
          'created_at': '2026-11-03T00:00:00Z',
        }
      ];

  String owner(http.Request r) {
    final token = r.headers['authorization']!.split(' ').last;
    return (jsonDecode(utf8
            .decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))))
        as Map)['sub'] as String;
  }

  Future<void> signIn(String id) async {
    account = id;
    ++login;
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
  }

  Future<ProviderContainer> mount(WidgetTester tester,
      {StateProvider<String>? group,
      Size size = const Size(390, 844),
      double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    final selected = group ?? StateProvider<String>((_) => _group);
    final router = GoRouter(initialLocation: '/group', routes: [
      GoRoute(
          path: '/group',
          builder: (_, __) => Consumer(
              builder: (_, ref, __) =>
                  GroupThreadScreen(groupId: ref.watch(selected)))),
      GoRoute(
          path: '/dm', builder: (_, __) => const Scaffold(body: Text('Inbox'))),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!))));
    await tester.pumpAndSettle();
    return container;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    account = _a;
    login = 0;
    requests = [];
    intercept = null;
    await Supabase.initialize(
        url: 'https://fixture.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((r) async {
          requests.add(r);
          if (r.url.path == '/auth/v1/token') {
            final payload = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': account,
                  'login': login,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                })))
                .replaceAll('=', '');
            return json(r, {
              'access_token': 'fixture.$payload.fixture',
              'refresh_token': 'fixture-refresh-$login',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': account,
                'aud': 'authenticated',
                'created_at': '2026-11-03T00:00:00Z'
              }
            });
          }
          final result = await intercept?.call(r);
          if (result != null) return result;
          if (r.url.path.endsWith('/group_chats')) {
            return json(r, {'name': 'Group ${r.url.queryParameters['id']}'});
          }
          if (r.url.path.endsWith('/group_members') && r.method == 'GET') {
            return json(r, [
              {
                'user_id': _peer,
                'profiles': {
                  'id': _peer,
                  'username': 'private_member_${owner(r)}',
                }
              }
            ]);
          }
          if (r.url.path.endsWith('/group_messages') && r.method == 'GET') {
            return json(
                r,
                messages(
                    'History ${owner(r)} ${r.url.queryParameters['group_id']}'));
          }
          if (r.url.path.endsWith('/profiles')) {
            return json(r, [
              {'id': _b, 'username': 'candidate'}
            ]);
          }
          return json(r, null);
        }));
    await signIn(_a);
    requests.clear();
  });
  tearDown(() async => Supabase.instance.dispose());

  testWidgets('account switch clears group history and draft', (tester) async {
    await mount(tester);
    expect(find.textContaining('History $_a'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A private draft');
    await signIn(_b);
    await tester.pumpAndSettle();
    expect(find.textContaining('History $_a'), findsNothing);
    expect(find.textContaining('History $_b'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh login to same owner clears draft, refresh retains it',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'old login draft');
    await Supabase.instance.client.auth.refreshSession();
    await tester.pumpAndSettle();
    expect(find.text('old login draft'), findsOneWidget);
    await signIn(_a);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reused group route cannot reuse another group draft or history',
      (tester) async {
    final group = StateProvider<String>((_) => _group);
    final container = await mount(tester, group: group);
    await tester.enterText(find.byType(TextField), 'first group draft');
    container.read(group.notifier).state = _other;
    await tester.pumpAndSettle();
    expect(find.textContaining('eq.$_group'), findsNothing);
    expect(find.textContaining('eq.$_other'), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signout removes history and composer and stops subscription',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'private draft');
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await tester.pumpAndSettle();
    expect(find.textContaining('History'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Мессеж үзэхийн тулд нэвтэрнэ үү.'), findsOneWidget);
    final count = requests.length;
    await tester.pump(const Duration(seconds: 16));
    expect(requests.length, count);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending send freezes draft and failure preserves exact text',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? send;
    intercept = (r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/group_messages')) {
        send = r;
        return held.future;
      }
      return null;
    };
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'keep this message');
    await tester.pump();
    await tester.tap(find.byTooltip('Мессеж илгээх'));
    await tester.pump();
    expect(send, isNotNull);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('keep this message'), findsOneWidget);
    held.complete(json(send!, {'message': 'fixture denied'}, 403));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.text('keep this message'), findsOneWidget);
    expect(
        requests.where((r) =>
            r.method == 'POST' && r.url.path.endsWith('/group_messages')),
        hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('late send failure cannot restore draft in next account',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? send;
    intercept = (r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/group_messages')) {
        send = r;
        return held.future;
      }
      return null;
    };
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'A only');
    await tester.pump();
    await tester.tap(find.byTooltip('Мессеж илгээх'));
    await tester.pump();
    await signIn(_b);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'B only');
    held.complete(json(send!, {'message': 'late fixture failure'}, 403));
    await tester.pumpAndSettle();
    expect(find.text('A only'), findsNothing);
    expect(find.text('B only'), findsOneWidget);
    expect(find.text('Илгээж чадсангүй. Дахин оролдоно уу.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member modal hides previous-account names on switch',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text('Group eq.$_group'));
    await tester.pumpAndSettle();
    expect(find.text('@private_member_$_a'), findsWidgets);
    await signIn(_b);
    await tester.pumpAndSettle();
    expect(find.text('@private_member_$_a'), findsNothing);
    expect(find.text('Гишүүн нэмэх'), findsNothing);
    expect(find.text('Нэвтрэх хаяг өөрчлөгдсөн байна.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member picker cannot submit selection after switching accounts',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text('Group eq.$_group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Гишүүн нэмэх'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@candidate'));
    await tester.pumpAndSettle();
    expect(find.text('Нэмэх (1)'), findsOneWidget);
    await signIn(_b);
    await tester.pumpAndSettle();
    expect(find.text('Нэмэх (1)'), findsNothing);
    expect(find.text('@candidate'), findsNothing);
    expect(
        requests.where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/group_members')),
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old leave confirmation cannot leave using a new account',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text('Group eq.$_group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Группээс гарах'));
    await tester.pumpAndSettle();
    await signIn(_b);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Гарах'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    expect(find.textContaining('History $_b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct-link back opens inbox without navigation exception',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Буцах'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('stalled send restores controls and reports uncertain result',
      (tester) async {
    final held = Completer<http.Response>();
    http.Request? send;
    intercept = (r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/group_messages')) {
        send = r;
        return held.future;
      }
      return null;
    };
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'uncertain message');
    await tester.pump();
    await tester.tap(find.byTooltip('Мессеж илгээх'));
    await tester.pump();
    expect(send, isNotNull);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.text('uncertain message'), findsOneWidget);
    expect(find.textContaining('Илгээсэн эсэхийг баталж чадсангүй.'),
        findsOneWidget);
    held.complete(json(send!, null));
    await tester.pumpAndSettle();
    expect(find.text('uncertain message'), findsOneWidget);
    expect(
        requests.where((r) =>
            r.method == 'POST' && r.url.path.endsWith('/group_messages')),
        hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small viewport with large text retains reachable group composer',
      (tester) async {
    await mount(tester, size: const Size(320, 640), scale: 1.5);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Group eq.$_group'));
    await tester.pumpAndSettle();
    expect(find.text('Группээс гарах'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
