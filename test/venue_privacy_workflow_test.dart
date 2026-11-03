import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/discovery/screens/privacy_screen.dart';
import 'package:night_owl_ub/features/map/providers/venue_provider.dart';
import 'package:night_owl_ub/features/profile/screens/venue_edit_screen.dart';
import 'package:night_owl_ub/features/profile/services/venue_editor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = '10000000-0000-4000-8000-000000000001';
  const second = '10000000-0000-4000-8000-000000000002';
  const venue = '20000000-0000-4000-8000-000000000001';
  var signedIn = first;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late http.Client transport;
  late VenueEditorService venueService;
  http.Response json(http.Request r, Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          request: r, headers: {'content-type': 'application/json'});
  Future<void> signIn(String owner) async {
    signedIn = owner;
    await Supabase.instance.client.auth.signInWithPassword(
        email: '$owner@example.test', password: 'fixture-only-password');
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    requests = [];
    respond = (r) async => json(r, []);
    transport = MockClient((r) async {
      requests.add(r);
      if (r.url.path == '/auth/v1/token') {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({
              'sub': signedIn,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
            })))
            .replaceAll('=', '');
        return json(r, {
          'access_token': 'fixture.$payload.fixture',
          'refresh_token': 'fixture-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': signedIn,
            'aud': 'authenticated',
            'created_at': '2026-11-03T00:00:00Z'
          }
        });
      }
      return respond(r);
    });
    await Supabase.initialize(
      url: 'https://audit-venue.example.test',
      anonKey: 'fixture-only-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage()),
      httpClient: transport,
    );
    venueService = VenueEditorService(httpClient: transport);
    await signIn(first);
    requests.clear();
  });
  tearDown(() async {
    transport.close();
    await Supabase.instance.dispose();
  });

  Future<void> renderVenue(WidgetTester tester,
      {bool existing = true,
      bool settle = true,
      Future<Uint8List?> Function()? picker}) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(initialLocation: '/venue/edit', routes: [
      GoRoute(
          path: '/venue/edit',
          builder: (_, __) => VenueEditScreen(
              venueId: existing ? venue : null,
              service: venueService,
              coverPicker: picker ??
                  () async =>
                      image.encodePng(image.Image(width: 2, height: 2)))),
      GoRoute(
          path: '/business',
          builder: (_, __) =>
              const Scaffold(body: Text('BUSINESS DESTINATION'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          refreshVenueCatalogProvider.overrideWith((_) => () {}),
        ],
        child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!))));
    if (settle) await tester.pumpAndSettle();
  }

  Map<String, dynamic> venueRow() => {
        'id': venue,
        'owner_id': first,
        'name': 'Original Venue',
        'venue_type': 'bar',
      };
  Iterable<http.Request> venueWrites() => requests.where((r) =>
      r.url.path == '/rest/v1/venues' && ['PATCH', 'POST'].contains(r.method));
  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Хадгалах'));
    await tester.tap(find.text('Хадгалах'));
    await tester.pump();
  }

  Future<void> pickCover(WidgetTester tester) async {
    await tester.tap(find.text('Cover зураг'));
    await tester.pumpAndSettle();
  }

  for (final emptyResponse in [false, true]) {
    testWidgets(
        'zero affected venue rows keep draft and allow retry, empty=$emptyResponse',
        (tester) async {
      var refuse = true;
      respond = (r) async {
        if (r.url.path == '/rest/v1/venues' && r.method == 'GET') {
          return json(r, venueRow());
        }
        if (refuse) {
          return emptyResponse
              ? http.Response('', 204, request: r)
              : json(r, []);
        }
        return json(r, [
          {'id': venue}
        ]);
      };
      await renderVenue(tester);
      await tester.enterText(find.byType(TextField).first, 'Preserved draft');
      await save(tester);
      await tester.pumpAndSettle();
      final patch = venueWrites().single;
      expect(patch.url.queryParameters['select'], 'id');
      expect(patch.url.queryParameters['id'], 'eq.$venue');
      expect(patch.url.queryParameters['owner_id'], 'eq.$first');
      expect(patch.headers['prefer'], 'return=representation');
      expect(find.text('BUSINESS DESTINATION'), findsNothing);
      expect(find.text('Хадгалагдлаа ✓'), findsNothing);
      expect(find.text('Хадгалж чадсангүй. Дахин оролдоно уу'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Preserved draft');
      refuse = false;
      await save(tester);
      await tester.pumpAndSettle();
      expect(venueWrites(), hasLength(2));
      expect(find.text('BUSINESS DESTINATION'), findsOneWidget);
      expect(find.text('Хадгалагдлаа ✓'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final change in ['other account', 'signout', 'same account relogin']) {
    testWidgets('$change during upload cannot publish the old venue draft',
        (tester) async {
      final uploadResult = Completer<http.Response>();
      http.Request? upload;
      respond = (r) async {
        if (r.url.path == '/rest/v1/venues' && r.method == 'GET') {
          return json(r, null);
        }
        if (r.url.path.startsWith('/storage/v1/object/venues/')) {
          upload = r;
          return uploadResult.future;
        }
        return json(r, []);
      };
      await renderVenue(tester, existing: false);
      await tester.enterText(
          find.byType(TextField).first, 'FIRST ACCOUNT DRAFT');
      await pickCover(tester);
      final firstToken =
          Supabase.instance.client.auth.currentSession!.accessToken;
      await save(tester);
      expect(upload, isNotNull);
      expect(upload!.url.path, contains('/$first/'));
      expect(upload!.headers['authorization'], 'Bearer $firstToken');
      expect(upload!.headers['content-type'], 'image/png');
      if (change == 'signout') {
        await tester.runAsync(() =>
            Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
      } else {
        await signIn(change == 'other account' ? second : first);
      }
      uploadResult.complete(json(upload!, {'Key': upload!.url.path}));
      await tester.pumpAndSettle();
      expect(venueWrites(), isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('FIRST ACCOUNT DRAFT'), findsNothing);
      expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
      expect(find.text('Хадгалагдлаа ✓'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late venue load cannot reveal an earlier account draft',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? load;
    respond = (r) async {
      load = r;
      return pending.future;
    };
    await renderVenue(tester, settle: false);
    await tester.pump();
    expect(load, isNotNull);
    await signIn(second);
    pending.complete(json(load!, venueRow()));
    await tester.pumpAndSettle();
    expect(find.text('Original Venue'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
    expect(venueWrites(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account switch during cover picker cannot start upload',
      (tester) async {
    final pending = Completer<Uint8List?>();
    respond = (r) async => json(r, null);
    await renderVenue(tester, existing: false, picker: () => pending.future);
    await tester.tap(find.text('Cover зураг'));
    await tester.pump();
    await signIn(second);
    pending.complete(image.encodePng(image.Image(width: 2, height: 2)));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.url.path.startsWith('/storage/')), isEmpty);
    expect(venueWrites(), isEmpty);
    expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed editor cannot save after cover upload completes',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? upload;
    respond = (r) async {
      if (r.method == 'GET') return json(r, null);
      upload = r;
      return pending.future;
    };
    await renderVenue(tester, existing: false);
    await tester.enterText(find.byType(TextField).first, 'Unsubmitted venue');
    await pickCover(tester);
    await save(tester);
    expect(upload, isNotNull);
    await tester.pumpWidget(const SizedBox());
    pending.complete(json(upload!, {'Key': upload!.url.path}));
    await tester.pumpAndSettle();
    expect(venueWrites(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'venue creation uploads captured bytes and confirms one inserted row',
      (tester) async {
    final pending = Completer<http.Response>();
    http.Request? upload;
    respond = (r) async {
      if (r.method == 'GET') return json(r, null);
      if (r.url.path.startsWith('/storage/')) {
        upload = r;
        return pending.future;
      }
      return json(
          r,
          [
            {'id': venue}
          ],
          201);
    };
    await renderVenue(tester, existing: false);
    await tester.enterText(find.byType(TextField).first, 'Saved venue');
    await pickCover(tester);
    final token = Supabase.instance.client.auth.currentSession!.accessToken;
    await save(tester);
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse);
    // A controller change while the request is pending cannot alter the saved snapshot.
    tester.widget<TextField>(find.byType(TextField).first).controller!.text =
        'Later edit';
    pending.complete(json(upload!, {'Key': upload!.url.path}));
    await tester.pumpAndSettle();
    final insert = venueWrites().single;
    final row = jsonDecode(insert.body) as Map;
    expect(insert.method, 'POST');
    expect(insert.headers['authorization'], 'Bearer $token');
    expect(row['owner_id'], first);
    expect(row['name'], 'Saved venue');
    expect(row['cover_url'], contains('/$first/'));
    expect(find.text('BUSINESS DESTINATION'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed cover upload keeps draft and does not write a venue',
      (tester) async {
    respond = (r) async {
      if (r.method == 'GET') return json(r, null);
      return json(r, {'message': 'Denied'}, 403);
    };
    await renderVenue(tester, existing: false);
    await tester.enterText(find.byType(TextField).first, 'Retryable venue');
    await pickCover(tester);
    await save(tester);
    await tester.pumpAndSettle();
    expect(venueWrites(), isEmpty);
    expect(
        find.text('Зураг илгээж чадсангүй. Дахин оролдоно уу'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled, isTrue);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Retryable venue');
    expect(tester.takeException(), isNull);
  });

  for (final delayed in [false, true]) {
    testWidgets(
        'rejected DM policy displays persisted selection, delayed=$delayed',
        (tester) async {
      final pending = Completer<http.Response>();
      http.Request? patch;
      respond = (r) async {
        if (r.url.path == '/rest/v1/profiles') {
          if (r.method == 'PATCH') {
            patch = r;
            if (delayed) return pending.future;
            return json(r, {'code': '42501', 'message': 'Denied'}, 403);
          }
          return json(r, {'is_private': false, 'dm_policy': 'everyone'});
        }
        return json(r, []);
      };
      await tester.pumpWidget(ProviderScope(
          overrides: [sessionUserIdProvider.overrideWithValue(first)],
          child: const MaterialApp(home: PrivacyScreen())));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Хэн ч бичихгүй').last);
      await tester.pump();
      expect(patch, isNotNull);
      if (delayed) {
        await tester.pump(const Duration(milliseconds: 100));
        pending.complete(
            json(patch!, {'code': '42501', 'message': 'Denied'}, 403));
      }
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byType(DropdownButton<String>))
              .value,
          'everyone');
      expect(find.textContaining('Энэ үйлдлийг хийх эрхгүй'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('successful DM policy write displays newly persisted policy',
      (tester) async {
    var policy = 'everyone';
    respond = (r) async {
      if (r.url.path == '/rest/v1/profiles') {
        if (r.method == 'PATCH') {
          policy = (jsonDecode(r.body) as Map)['dm_policy'] as String;
          return json(r, {'id': first});
        }
        return json(r, {'is_private': false, 'dm_policy': policy});
      }
      return json(r, []);
    };
    await tester.pumpWidget(ProviderScope(
        overrides: [sessionUserIdProvider.overrideWithValue(first)],
        child: const MaterialApp(home: PrivacyScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Хэн ч бичихгүй').last);
    await tester.pumpAndSettle();
    expect(policy, 'nobody');
    expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        policy);
    expect(tester.takeException(), isNull);
  });
}
