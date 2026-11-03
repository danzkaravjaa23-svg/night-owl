import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/dm/screens/dm_list_screen.dart';
import 'package:night_owl_ub/core/theme/app_text_styles.dart';
import 'package:night_owl_ub/features/notifications/screens/notifications_screen.dart';
import 'package:night_owl_ub/features/search/screens/search_screen.dart';

const _a = '10000000-0000-4000-8000-000000000001';
const _b = '10000000-0000-4000-8000-000000000002';
const _partner = '10000000-0000-4000-8000-000000000003';
const _group = '10000000-0000-4000-8000-000000000004';

http.Response _reply(http.Request r, Object? data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        request: r,
        headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _notif(String message) => {
      'id': 'notice',
      'type': 'follow',
      'is_read': false,
      'message': message,
      'created_at': '2026-11-03T00:00:00Z',
      'profiles': {'id': _partner, 'username': 'friend', 'avatar_url': null},
    };

Map<String, dynamic> _conversation(String message) => {
      'partner_id': _partner,
      'partner_username': 'fixture_friend',
      'partner_avatar_url': null,
      'partner_last_seen_at': null,
      'last_body': message,
      'last_at': '2026-11-03T00:00:00Z',
      'last_sender_id': _partner,
      'unread_count': 2,
    };

Map<String, dynamic> _person(String name) => {
      'id': _partner,
      'username': name,
      'full_name': '',
      'avatar_url': null,
      'is_verified': false,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String loginOwner;
  late List<http.Request> requests;
  late Map<String, List<Map<String, dynamic>>> notices;
  late Map<String, List<Map<String, dynamic>>> conversations;
  late List<Map<String, dynamic>> groups;
  Future<http.Response?> Function(http.Request)? intercept;

  Future<void> signIn(String owner) async {
    loginOwner = owner;
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.test', password: 'fixture-only');
  }

  String requestOwner(http.Request r) {
    final token = r.headers['authorization']?.split(' ').last ?? '';
    if (!token.contains('.')) return '';
    return (jsonDecode(utf8
            .decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))))
        as Map)['sub'] as String;
  }

  Future<GoRouter> mount(
    WidgetTester tester,
    Widget screen, {
    bool settle = true,
    Size size = const Size(390, 1000),
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => screen),
      for (final path in ['/creator/:id', '/post/:id', '/dm/:id', '/group/:id'])
        GoRoute(
            path: path,
            builder: (_, __) =>
                Scaffold(appBar: AppBar(), body: const Text('Destination'))),
      GoRoute(
          path: '/feed',
          builder: (_, __) => const Scaffold(body: Text('Feed'))),
      GoRoute(
          path: '/privacy',
          builder: (_, __) => const Scaffold(body: Text('Privacy'))),
    ]);
    addTearDown(router.dispose);
    await tester.runAsync(() => GoogleFonts.pendingFonts([
          AppTextStyles.h1,
          AppTextStyles.h3,
          AppTextStyles.bodyMd,
          AppTextStyles.labelLg,
          AppTextStyles.labelMd,
          AppTextStyles.displayMd,
        ]));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale),
                    viewInsets: EdgeInsets.only(bottom: keyboard)),
                child: child!))));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return router;
  }

  Future<void> prepareGroup(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Групп чат үүсгэх'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Fixture group');
    await tester.tap(find.text('@candidate'));
    await tester.pumpAndSettle();
    expect(find.text('Групп үүсгэх (2)'), findsOneWidget);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    loginOwner = _a;
    requests = [];
    notices = {
      _a: [_notif('A private notification')],
      _b: [_notif('B private notification')]
    };
    conversations = {
      _a: [_conversation('A private message')],
      _b: [_conversation('B private message')]
    };
    groups = [];
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
                  'sub': loginOwner,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                })))
                .replaceAll('=', '');
            return _reply(r, {
              'access_token': 'fixture.$payload.fixture',
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': loginOwner,
                'aud': 'authenticated',
                'created_at': '2026-11-03T00:00:00Z'
              }
            });
          }
          final overridden = await intercept?.call(r);
          if (overridden != null) return overridden;
          if (r.method == 'PATCH') return _reply(r, []);
          if (r.url.path == '/auth/v1/logout') return _reply(r, {});
          if (r.url.path == '/rest/v1/notifications') {
            return _reply(r, notices[requestOwner(r)] ?? []);
          }
          if (r.url.path == '/rest/v1/rpc/dm_conversations') {
            return _reply(r, conversations[requestOwner(r)] ?? []);
          }
          if (r.url.path == '/rest/v1/group_members') return _reply(r, groups);
          return _reply(r, []);
        }));
    await signIn(_a);
  });
  tearDown(() async => Supabase.instance.dispose());

  testWidgets(
      'Notifications remain unread on open, failed mark-all retries without optimism',
      (tester) async {
    var fail = true;
    intercept = (r) async => r.method == 'PATCH'
        ? (fail ? _reply(r, {'message': 'denied'}, 403) : _reply(r, []))
        : null;
    await mount(tester, const NotificationsScreen());
    expect(find.text('1 шинэ'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
    await tester.tap(find.text('Бүгдийг уншсан'));
    await tester.pumpAndSettle();
    expect(find.text('1 шинэ'), findsOneWidget);
    expect(find.text('Алдаа гарлаа — дахин оролдоно уу'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Бүгдийг уншсан'));
    await tester.pumpAndSettle();
    expect(find.text('1 шинэ'), findsNothing);
    final writes = requests.where((r) => r.method == 'PATCH').toList();
    expect(writes, hasLength(2));
    expect(writes.every((r) => r.url.queryParameters['user_id'] == 'eq.$_a'),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Pending read-all deduplicates and late failure cannot affect the next account',
      (tester) async {
    final pending = Completer<void>();
    intercept = (r) async {
      if (r.method != 'PATCH') return null;
      await pending.future;
      return _reply(r, {'message': 'late failure'}, 403);
    };
    await mount(tester, const NotificationsScreen());
    await tester.tap(find.text('Бүгдийг уншсан'));
    await tester.pump();
    expect(find.text('1 шинэ'), findsOneWidget);
    await tester.tap(find.text('Бүгдийг уншсан'));
    await tester.pump();
    expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
    await signIn(_b);
    await tester.pumpAndSettle();
    expect(find.textContaining('A private notification', findRichText: true),
        findsNothing);
    expect(find.textContaining('B private notification', findRichText: true),
        findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('1 шинэ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final notification in [true, false]) {
    testWidgets(
        '${notification ? 'Notifications' : 'Inbox'} discards a late account-A load and clears on logout',
        (tester) async {
      final pending = Completer<void>();
      final path = notification
          ? '/rest/v1/notifications'
          : '/rest/v1/rpc/dm_conversations';
      intercept = (r) async {
        if (r.url.path != path || requestOwner(r) != _a) return null;
        await pending.future;
        return _reply(r, notification ? notices[_a] : conversations[_a]);
      };
      await mount(tester,
          notification ? const NotificationsScreen() : const DmListScreen(),
          settle: false);
      await signIn(_b);
      await tester.pumpAndSettle();
      expect(
          find.textContaining('B private', findRichText: true), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(
          find.textContaining('A private', findRichText: true), findsNothing);
      await tester.runAsync(() =>
          Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('B private', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'Notification failure shows retry without marking unseen rows read',
      (tester) async {
    var fail = true;
    intercept = (r) async => fail && r.url.path == '/rest/v1/notifications'
        ? _reply(r, {'message': 'offline'}, 403)
        : null;
    await mount(tester, const NotificationsScreen());
    expect(find.text('Дахин оролдох'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
    fail = false;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('1 шинэ'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Notification row deduplicates pending read and opens one destination',
      (tester) async {
    final pending = Completer<void>();
    intercept = (r) async {
      if (r.method != 'PATCH') return null;
      await pending.future;
      return _reply(r, []);
    };
    final router = await mount(tester, const NotificationsScreen());
    final row =
        find.textContaining('A private notification', findRichText: true);
    await tester.tap(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('1 шинэ'), findsNothing);
    expect(router.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Notification header remains reachable at 320px and 2x text',
      (tester) async {
    await mount(tester, const NotificationsScreen(),
        size: const Size(320, 640), scale: 2);
    expect(find.text('Бүгдийг уншсан').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Дахин ачаалах').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Inbox filters group names as well as message conversations',
      (tester) async {
    groups = [
      {
        'group_id': _group,
        'group_chats': {
          'id': _group,
          'name': 'Jazz group',
          'created_by': _a,
          'created_at': '2026-11-03T00:00:00Z'
        }
      }
    ];
    await mount(tester, const DmListScreen());
    await tester.enterText(find.byType(TextField).first, 'Jazz');
    await tester.pumpAndSettle();
    expect(find.text('Jazz group'), findsOneWidget);
    expect(find.text('A private message'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'unmatched');
    await tester.pumpAndSettle();
    expect(find.text('Jazz group'), findsNothing);
    expect(find.text('Тохирох мессеж олдсонгүй'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Initial group failure still shows direct conversations with retry',
      (tester) async {
    intercept = (r) async => r.url.path == '/rest/v1/group_members'
        ? _reply(r, {'message': 'unavailable'}, 403)
        : null;
    await mount(tester, const DmListScreen());
    expect(find.text('A private message'), findsOneWidget);
    expect(find.text('1 шинэ'), findsOneWidget);
    expect(find.text('Шинэчилж чадсангүй'), findsOneWidget);
    expect(find.text('Ачаалж чадсангүй'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Failed group refresh keeps old conversations and shows a retry',
      (tester) async {
    await mount(tester, const DmListScreen());
    intercept = (r) async => r.url.path == '/rest/v1/group_members'
        ? _reply(r, {'message': 'unavailable'}, 403)
        : null;
    await tester.tap(find.byTooltip('Дахин ачаалах'));
    await tester.pumpAndSettle();
    expect(find.text('A private message'), findsOneWidget);
    expect(find.text('Шинэчилж чадсангүй'), findsOneWidget);
    intercept = null;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('Шинэчилж чадсангүй'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'An old inbox action sheet cannot update the newly signed-in account',
      (tester) async {
    await mount(tester, const DmListScreen());
    await tester.longPress(find.text('A private message'));
    await tester.pumpAndSettle();
    expect(find.text('Уншсан болгох'), findsOneWidget);
    await signIn(_b);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уншсан болгох'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
    expect(find.text('B private message'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Suggested search is visibly focused and activates with Enter',
      (tester) async {
    intercept = (r) async => r.url.path == '/rest/v1/profiles' &&
            r.url.queryParameters.containsKey('or')
        ? _reply(r, [_person('keyboard_result')])
        : null;
    await mount(tester, const SearchScreen());
    final suggestion = find.text('Караоке');
    for (var step = 0;
        step < 12 && !Focus.of(tester.element(suggestion)).hasFocus;
        step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(Focus.of(tester.element(suggestion)).hasFocus, isTrue);
    final focusSurface = tester.widget<Container>(find.ancestor(
      of: suggestion,
      matching: find.byWidgetPredicate((widget) =>
          widget is Container && widget.foregroundDecoration != null),
    ));
    final border =
        (focusSurface.foregroundDecoration! as BoxDecoration).border! as Border;
    expect(border.top.width, greaterThanOrEqualTo(2));
    expect(border.top.color.a, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Караоке');
    expect(find.text('@keyboard_result'), findsOneWidget);
    final queries = requests.where((r) =>
        r.url.path == '/rest/v1/profiles' &&
        r.url.queryParameters.containsKey('or'));
    expect(queries, hasLength(1));
    expect(queries.single.url.queryParameters['or'], contains('Караоке'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Search ignores the first A result after typing A, B, A',
      (tester) async {
    final pending = Completer<void>();
    var matching = 0;
    intercept = (r) async {
      if (r.url.path != '/rest/v1/profiles' ||
          !r.url.queryParameters.containsKey('or')) {
        return null;
      }
      if (r.url.queryParameters['or']!.contains('alpha')) {
        matching++;
        if (matching == 1) {
          await pending.future;
          return _reply(r, [_person('stale_alpha')]);
        }
        return _reply(r, [_person('latest_alpha')]);
      }
      return _reply(r, [_person('beta')]);
    };
    await mount(tester, const SearchScreen());
    final field = find.byType(TextField);
    await tester.enterText(field, 'alpha');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(field, 'beta');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('@beta'), findsOneWidget);
    await tester.enterText(field, 'alpha');
    await tester.pump();
    expect(find.text('@beta'), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('@latest_alpha'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('@latest_alpha'), findsOneWidget);
    expect(find.text('@stale_alpha'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Pending inbox read action cannot be repeated and failures retain unread state',
      (tester) async {
    final pending = Completer<void>();
    intercept = (r) async {
      if (r.method != 'PATCH') return null;
      await pending.future;
      return _reply(r, {'message': 'denied'}, 403);
    };
    await mount(tester, const DmListScreen());
    final row = find.text('A private message');
    await tester.longPress(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Уншсан болгох'));
    await tester.pumpAndSettle();
    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(find.text('Уншсан болгох'), findsNothing);
    final writes = requests.where((r) => r.method == 'PATCH').toList();
    expect(writes, hasLength(1));
    expect(writes.single.url.queryParameters['receiver_id'], 'eq.$_a');
    expect(find.text('1 шинэ'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Амжилтгүй боллоо. Дахин оролдоно уу.'), findsOneWidget);
    expect(find.text('1 шинэ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Search discover load failure can retry without trapping the loading state',
      (tester) async {
    var fail = true;
    intercept = (r) async => fail && r.url.path == '/rest/v1/posts'
        ? _reply(r, {'message': 'denied'}, 403)
        : null;
    await mount(tester, const SearchScreen());
    expect(find.text('Дахин оролдох'), findsOneWidget);
    fail = false;
    await tester.ensureVisible(find.text('Дахин оролдох'));
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('Дахин оролдох'), findsNothing);
    expect(find.text('Пост алга байна'), findsOneWidget);
    expect(requests.where((r) => r.url.path == '/rest/v1/posts'), hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Search preserves literal underscores and clearing rejects a late result',
      (tester) async {
    final pending = Completer<void>();
    intercept = (r) async {
      if (!r.url.queryParameters.containsKey('or')) return null;
      expect(r.url.queryParameters['or'], contains(r'my\_name'));
      await pending.future;
      return _reply(r, [_person('my_name')]);
    };
    await mount(tester, const SearchScreen());
    await tester.enterText(find.byType(TextField), 'my_name');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Цэвэрлэх'));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('@my_name'), findsNothing);
    expect(find.text('Санал болгох хайлт'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Search clears a pending query and account-specific results on account change',
      (tester) async {
    final pending = Completer<void>();
    intercept = (r) async {
      if (r.url.path != '/rest/v1/profiles' ||
          !r.url.queryParameters.containsKey('or')) {
        return null;
      }
      await pending.future;
      return _reply(r, [_person('account_a_result')]);
    };
    await mount(tester, const SearchScreen());
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 350));
    await signIn(_b);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('@account_a_result'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Search errors retry at 320px, 2x text and an open keyboard',
      (tester) async {
    var fail = true;
    intercept = (r) async => r.url.path == '/rest/v1/profiles' &&
            r.url.queryParameters.containsKey('or')
        ? (fail
            ? _reply(r, {'message': 'offline'}, 403)
            : _reply(r, [_person('recovered')]))
        : null;
    await mount(tester, const SearchScreen(),
        size: const Size(320, 640), scale: 2, keyboard: 280);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Хайж чадсангүй'), findsOneWidget);
    expect(tester.takeException(), isNull);
    fail = false;
    await tester.ensureVisible(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(
        requests.where((r) =>
            r.url.path == '/rest/v1/profiles' &&
            r.url.queryParameters.containsKey('or')),
        hasLength(2),
        reason: 'The recovery action must issue exactly one new search.');
    expect(find.text('@recovered'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Wildcard-only search does not send an unbounded people query',
      (tester) async {
    await mount(tester, const SearchScreen());
    await tester.enterText(find.byType(TextField), '%_*(),');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Илэрц олдсонгүй'), findsOneWidget);
    expect(requests.where((r) => r.url.queryParameters.containsKey('or')),
        isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Group sheet opened by A cannot submit after switching to B',
      (tester) async {
    intercept = (r) async => r.url.path == '/rest/v1/profiles' &&
            r.url.queryParameters['id'] == 'neq.$_a'
        ? _reply(r, [_person('candidate')])
        : null;
    await mount(tester, const DmListScreen());
    await prepareGroup(tester);
    await signIn(_b);
    await tester.pumpAndSettle();
    expect(find.text('Групп үүсгэх (2)'), findsNothing);
    expect(
        find.text(
            'Нэвтрэх бүртгэл өөрчлөгдсөн. Групп үүсгэх цонхыг дахин нээнэ үү.'),
        findsOneWidget);
    expect(requests.where((r) => r.url.path == '/rest/v1/rpc/create_group'),
        isEmpty);
    await tester.tap(find.text('Хаах'));
    await tester.pumpAndSettle();
    expect(find.text('B private message'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final nextAccount in [_a, _b]) {
    testWidgets(
        'Late group success cannot navigate after ${nextAccount == _a ? 'same-account new sign-in' : 'account switch'}',
        (tester) async {
      final pending = Completer<void>();
      intercept = (r) async {
        if (r.url.path == '/rest/v1/profiles' &&
            r.url.queryParameters['id'] == 'neq.$_a') {
          return _reply(r, [_person('candidate')]);
        }
        if (r.url.path == '/rest/v1/rpc/create_group') {
          await pending.future;
          return _reply(r, _group);
        }
        return null;
      };
      final router = await mount(tester, const DmListScreen());
      await prepareGroup(tester);
      await tester.tap(find.text('Групп үүсгэх (2)'));
      await tester.pump();
      expect(requests.where((r) => r.url.path == '/rest/v1/rpc/create_group'),
          hasLength(1));
      await signIn(nextAccount);
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Destination'), findsNothing);
      expect(
          find.text(
              'Нэвтрэх бүртгэл өөрчлөгдсөн. Групп үүсгэх цонхыг дахин нээнэ үү.'),
          findsOneWidget);
      await tester.tap(find.text('Хаах'));
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'Zero-row group RPC is a visible failure, retry opens only a valid UUID',
      (tester) async {
    var succeed = false;
    intercept = (r) async {
      if (r.url.path == '/rest/v1/profiles' &&
          r.url.queryParameters['id'] == 'neq.$_a') {
        return _reply(r, [_person('candidate')]);
      }
      if (r.url.path == '/rest/v1/rpc/create_group') {
        return _reply(r, succeed ? _group : []);
      }
      return null;
    };
    await mount(tester, const DmListScreen());
    await prepareGroup(tester);
    await tester.tap(find.text('Групп үүсгэх (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Групп үүсгэж чадсангүй'), findsOneWidget);
    expect(find.text('Destination'), findsNothing);
    expect(
        requests.where((r) =>
            r.method == 'POST' &&
            !r.url.path.contains('/rpc/') &&
            !r.url.path.contains('/auth/')),
        isEmpty);
    succeed = true;
    await tester.tap(find.text('Групп үүсгэх (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
    expect(requests.where((r) => r.url.path == '/rest/v1/rpc/create_group'),
        hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Group creation remains valid through a refresh of the same session',
      (tester) async {
    final pending = Completer<void>();
    intercept = (r) async {
      if (r.url.path == '/rest/v1/profiles' &&
          r.url.queryParameters['id'] == 'neq.$_a') {
        return _reply(r, [_person('candidate')]);
      }
      if (r.url.path == '/rest/v1/rpc/create_group') {
        await pending.future;
        return _reply(r, _group);
      }
      return null;
    };
    await mount(tester, const DmListScreen());
    await prepareGroup(tester);
    await tester.tap(find.text('Групп үүсгэх (2)'));
    await tester.pump();
    await Supabase.instance.client.auth.refreshSession();
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsOneWidget);
    expect(requests.where((r) => r.url.path == '/rest/v1/rpc/create_group'),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Closing a pending group sheet does not reopen it on late success',
      (tester) async {
    final pending = Completer<void>();
    intercept = (r) async {
      if (r.url.path == '/rest/v1/profiles' &&
          r.url.queryParameters['id'] == 'neq.$_a') {
        return _reply(r, [_person('candidate')]);
      }
      if (r.url.path == '/rest/v1/rpc/create_group') {
        await pending.future;
        return _reply(r, _group);
      }
      return null;
    };
    await mount(tester, const DmListScreen());
    await prepareGroup(tester);
    await tester.tap(find.text('Групп үүсгэх (2)'));
    await tester.pump();
    Navigator.of(tester.element(find.text('Групп чат үүсгэх'))).pop();
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Destination'), findsNothing);
    expect(find.text('A private message'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
