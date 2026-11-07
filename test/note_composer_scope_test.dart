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
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/features/dm/services/note_service.dart';
import 'package:night_owl_ub/features/dm/widgets/notes_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = '10000000-0000-4000-8000-000000000001';
  const second = '10000000-0000-4000-8000-000000000002';
  late String account;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late http.Client transport;

  http.Response json(http.Request request, Object? body) =>
      http.Response(jsonEncode(body), 200,
          request: request, headers: {'content-type': 'application/json'});

  Future<void> signIn(String owner) async {
    account = owner;
    await Supabase.instance.client.auth.signInWithPassword(
        email: '$owner@example.test', password: 'fixture-password');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    account = first;
    requests = [];
    respond = (request) async {
      if (request.url.path.endsWith('/profiles')) {
        return json(request, {'id': account, 'username': 'fixture'});
      }
      return json(request, []);
    };
    transport = MockClient((request) async {
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
            'created_at': '2026-11-03T00:00:00Z',
          },
        });
      }
      return respond(request);
    });
    await Supabase.initialize(
        url: 'https://notes-scope.example.test',
        anonKey: 'fixture-public-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: transport);
    await signIn(first);
    requests.clear();
  });

  tearDown(() async {
    await Supabase.instance.dispose();
    transport.close();
  });

  Future<void> render(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          noteServiceProvider.overrideWithValue(NoteService(
              client: Supabase.instance.client, transport: transport)),
        ],
        child: MaterialApp(
            theme: AppTheme.dark, home: const Scaffold(body: NotesRow()))));
  }

  for (final replacement in [first, second]) {
    testWidgets(
        '${replacement == first ? 'Relogin' : 'Account switch'} clears draft and closes its venue picker',
        (tester) async {
      await render(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Note үлдээх...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Private draft');
      await tester.tap(find.text('Газар тэмдэглэх (заавал биш)'));
      await tester.pumpAndSettle();
      expect(find.text('Газар сонгох'), findsOneWidget);
      await tester.runAsync(() => signIn(replacement));
      await tester.pumpAndSettle();
      expect(find.text('Газар сонгох'), findsNothing);
      expect(find.text('Private draft'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
      expect(
          requests.where((request) =>
              request.method != 'GET' && request.url.path.endsWith('/notes')),
          isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final (status, message) in [
    ('approved', 'Нийтлэгдлээ'),
    ('pending', 'Шалгалтад байна. Модератор баталсны дараа бусдад харагдана.'),
    (null, 'Хадгалагдлаа'),
  ]) {
    testWidgets('note save reports the saved $status state truthfully',
        (tester) async {
      respond = (request) async {
        if (request.url.path.endsWith('/profiles')) {
          return json(request, {'id': account, 'username': 'fixture'});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/notes')) {
          expect(request.url.queryParameters['select'],
              'user_id,text,moderation_status');
          return json(request, [
            {
              'user_id': account,
              'text': 'Tonight at the bar',
              if (status != null) 'moderation_status': status,
            }
          ]);
        }
        return json(request, []);
      };
      await render(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Note үлдээх...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tonight at the bar');
      await tester.tap(find.text('Хуваалцах'));
      await tester.pumpAndSettle();
      expect(
          requests.where((request) =>
              request.method == 'POST' && request.url.path.endsWith('/notes')),
          hasLength(1));
      expect(find.byType(TextField), findsNothing);
      expect(find.text(message), findsOneWidget);
      if (status != 'approved') expect(find.text('Нийтлэгдлээ'), findsNothing);
      expect(find.textContaining('Шалгалтад илгээлээ'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a late profile load cannot resume the old account note query',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? oldProfile;
    respond = (request) async {
      if (request.url.path.endsWith('/profiles')) {
        if (request.url.queryParameters['id'] == 'eq.$first') {
          oldProfile = request;
          return pending.future;
        }
        final profile = {'id': second, 'username': 'current_account'};
        return json(
            request,
            request.url.queryParameters.containsKey('id') &&
                    request.url.queryParameters['id']!.startsWith('eq.')
                ? profile
                : [profile]);
      }
      if (request.url.path.endsWith('/notes')) {
        return json(request, [
          {
            'user_id': second,
            'text': 'Current account note',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }
        ]);
      }
      return json(request, []);
    };
    await render(tester);
    await tester.pump();
    expect(oldProfile, isNotNull);
    await tester.runAsync(() => signIn(second));
    await tester.pumpAndSettle();
    expect(find.text('Current account note'), findsOneWidget);
    final noteReads =
        requests.where((request) => request.url.path.endsWith('/notes')).length;
    pending
        .complete(json(oldProfile!, {'id': first, 'username': 'old_account'}));
    await tester.pumpAndSettle();
    expect(find.text('Current account note'), findsOneWidget);
    expect(requests.where((request) => request.url.path.endsWith('/notes')),
        hasLength(noteReads));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
